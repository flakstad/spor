# Maven Central release recipe

VevDB publishes two JVM coordinates from one coordinated engine release:

- `com.vevdb:vev-java`
- `com.vevdb:vev-clj`, which depends on the same-version `vev-java`

The Java artifact contains every verified native engine as a classpath
resource. There is no public platform selector dependency.

## One-time account setup

1. Sign in at <https://central.sonatype.com>.
2. Open **View Namespaces**, add `com.vevdb`, and copy its verification key.
3. At the DNS provider for `vevdb.com`, add the key as a TXT record on the
   zone apex (`@` or a blank host, depending on the provider).
4. Wait until `dig +short TXT vevdb.com` returns the exact key. Only then ask
   Sonatype to verify the namespace; a premature attempt can be delayed by
   cached negative DNS answers.
5. Generate a Central Portal user token at
   <https://central.sonatype.com/usertoken>. Save its generated username and
   password in a password manager; they cannot be retrieved later.
6. Create a dedicated OpenPGP signing key for releases. Publish its public key
   to a public keyserver and export the private key in ASCII-armored form.

Store these GitHub Actions secrets on `vevdb/vev`:

- `CENTRAL_USERNAME`
- `CENTRAL_PASSWORD`
- `CENTRAL_GPG_PRIVATE_KEY`
- `CENTRAL_GPG_PASSPHRASE`
- `CENTRAL_GPG_KEY_ID`

Never put these values in a repository, issue, pull request, build log, or chat.

## Files in a deployment

For each coordinate and version, the Maven-layout directory must contain:

```text
com/vevdb/vev-java/VERSION/
  vev-java-VERSION.pom
  vev-java-VERSION.jar
  vev-java-VERSION-sources.jar
  vev-java-VERSION-javadoc.jar

com/vevdb/vev-clj/VERSION/
  vev-clj-VERSION.pom
  vev-clj-VERSION.jar
  vev-clj-VERSION-sources.jar
  vev-clj-VERSION-javadoc.jar
```

Every POM, main JAR, sources JAR, and Javadoc JAR needs:

- a detached ASCII-armored GPG signature with the `.asc` suffix
- an MD5 checksum with the `.md5` suffix
- a SHA-1 checksum with the `.sha1` suffix

Do not sign checksum files. Do not add checksums for `.asc` files. SHA-256 and
SHA-512 may be included as additional verification.

The POMs must carry name, description, project URL, license, developer, and SCM
metadata. `vev-clj` must declare an ordinary compile dependency on the exact
same version of `com.vevdb:vev-java`.

## First publication

1. Merge and tag the coordinated version in `vev`, `vev-java`, and `vev-clj`.
   Use a new version: Maven Central artifacts are immutable.
2. Let the five-platform release gate build and smoke the native SDKs and the
   combined Java artifact. It also generates and validates the sources and
   Javadoc artifacts required by Central.
3. Run the **Stage Maven Central deployment** workflow with the published
   GitHub release tag and artifact version. The workflow downloads the verified
   release files, constructs the Maven directory tree, signs the eight primary
   files, adds required checksums, and uploads a user-managed deployment.
   Locally, the equivalent bundle command is:

   ```sh
   scripts/package_maven_central_bundle.sh \
     VERSION \
     /path/to/jvm-release-files \
     central-bundle.zip
   ```

   Paths inside the ZIP begin at `com/`, not at an extra staging directory.
4. Create the Portal bearer token:

   ```sh
   CENTRAL_BEARER="$(
     printf '%s:%s' "$CENTRAL_USERNAME" "$CENTRAL_PASSWORD" | base64
   )"
   ```

5. The workflow uploads the bundle as user-managed. The equivalent API call is:

   ```sh
   DEPLOYMENT_ID="$(
     curl --fail-with-body \
       --request POST \
       --header "Authorization: Bearer $CENTRAL_BEARER" \
       --form bundle=@central-bundle.zip \
       "https://central.sonatype.com/api/v1/publisher/upload?publishingType=USER_MANAGED&name=VevDB-VERSION"
   )"
   ```

6. Poll validation:

   ```sh
   curl --fail-with-body \
     --request POST \
     --header "Authorization: Bearer $CENTRAL_BEARER" \
     "https://central.sonatype.com/api/v1/publisher/status?id=$DEPLOYMENT_ID"
   ```

7. When the state is `VALIDATED`, resolve both artifacts through Central's
   deployment-testing Maven endpoint into a fresh cache. Run the Java and
   Clojure durable open/write/reopen acceptance tests with `VEV_LIB` unset.
8. Publish the validated deployment in the Portal UI. Keep the first release
   user-managed; automatic publication can be enabled after the process has
   proved reliable.
9. Wait for the state `PUBLISHED`, then resolve both coordinates anonymously
   from `https://repo1.maven.org/maven2/` into another empty cache.

The recommended first publication under `com.vevdb` is `0.2.0-rc.1`, followed
by `0.2.0` after consumer validation.

## Official references

- <https://central.sonatype.org/register/namespace/>
- <https://central.sonatype.org/publish/requirements/>
- <https://central.sonatype.org/publish/generate-portal-token/>
- <https://central.sonatype.org/publish/publish-portal-api/>
