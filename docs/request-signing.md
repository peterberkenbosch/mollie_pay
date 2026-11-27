# Request signing

Mollie can require that every API request is signed with an Ed25519 key
([request signing](https://docs.mollie.com/reference/request-signing)). You
register a public key on an API key in the Mollie dashboard; from then on
Mollie answers `401` to any request made with that API key that does not
carry a valid signature. MolliePay signs every request it sends once it has
the private key.

What this buys you: an API key that leaks on its own can no longer be used.
What it does not: if the API key and the private key leak together, signing
protects nothing.

## Set it up

1. **Generate a key pair** in your app:

   ```sh
   bin/rails mollie_pay:request_signing:generate
   ```

   It prints the public key as PEM and the private key as one line. Nothing is
   written to disk, so the private key is shown once.

2. **Store the private key** as a secret (see [Where to keep the private
   key](#where-to-keep-the-private-key)) and point the engine at it:

   ```ruby
   # config/initializers/mollie_pay.rb
   config.request_signing_key = ENV["MOLLIE_REQUEST_SIGNING_KEY"]
   ```

3. **Register the public key** in the Mollie dashboard: Developers > API
   keys, the "Public key" field of a new API key. Paste the whole PEM,
   including the `BEGIN` and `END` lines. The dashboard offers the field when
   a key is created, so this gives you a new API key: deploy it together with
   the private key.

4. **Check it** from the deployed app:

   ```sh
   bin/rails mollie_pay:request_signing:verify
   ```

   | Answer | Meaning |
   |---|---|
   | `OK` | Mollie refuses unsigned requests for this API key and accepts the app's signature. |
   | `Not enforced` | Mollie accepts unsigned requests, so no public key is registered on this API key. |
   | `Refused` | Mollie enforces signing and rejects the app's signature: the registered public key is not this private key's, the API key is wrong, or the clock is off. |

   The check makes two requests that read the payment methods and change
   nothing.

Signing is harmless while Mollie does not enforce it: an API key without a
public key answers signed requests as usual. So the private key can go out
before the API key that needs it.

## Where to keep the private key

The private key is a secret of the same weight as the API key. It belongs
where your other production secrets live, and nowhere else.

**An environment variable from a secret manager.** The single line the
generator prints has no line breaks and no quotes to escape, so it fits any
secret store, `.env` file or deploy tool:

```sh
MOLLIE_REQUEST_SIGNING_KEY=MC4CAQAwBQYDK2VwBCIEI...
```

**Rails encrypted credentials.** `bin/rails credentials:edit --environment production`:

```yaml
mollie:
  request_signing_key: MC4CAQAwBQYDK2VwBCIEI...
```

```ruby
config.request_signing_key = Rails.application.credentials.dig(:mollie, :request_signing_key)
```

`request_signing_key` takes three forms, so whatever your secret store makes
of the key is read:

| Form | Example |
|---|---|
| The single line | `MC4CAQAwBQYDK2VwBCIEI...` |
| PEM | `-----BEGIN PRIVATE KEY-----`, the line, `-----END PRIVATE KEY-----` |
| PEM with `\n` written out | `-----BEGIN PRIVATE KEY-----\nMC4C...\n-----END PRIVATE KEY-----\n` |

A value that is not an Ed25519 private key, the public key included, raises
`MolliePay::ConfigurationError` when the app boots, not on the first payment.

## Rules for the private key

- **Never in the repository.** Not in the initializer, not in a `.env` file
  that is committed, not in a fixture. Not in a chat, a ticket, a CI log or a
  screenshot either.
- **One key pair per API key.** A pair for production, another for staging,
  another for a developer's test key. A test pair that leaks then says
  nothing about production.
- **Only where Mollie is called.** The web and job processes need it. CI does
  not: the test suite stubs Mollie and needs no key at all.
- **Generate it where you trust the screen.** The generator prints the key to
  the terminal. Copy it into the secret store, then clear the scrollback. If
  you would sooner have files, see [With openssl](#with-openssl).
- **Keep the clock right.** Mollie rejects a signature whose timestamp is more
  than 5 minutes from its own time. A server without time synchronisation
  will start failing with `401`.

MolliePay never logs the key, and `MolliePay.configuration.inspect` leaves it
out, as it does the API key.

## When something goes wrong

- **The private key is lost.** It cannot be recovered and the public key is
  no help. Generate a new pair and create a new API key with the new public
  key.
- **The private key, or both keys, leaked.** Delete the API key in the Mollie
  dashboard first: that ends what the leak can do. Then set up a new API key
  with a new pair.
- **Which public key belongs to the key this app has?**

  ```sh
  bin/rails mollie_pay:request_signing:public_key
  ```

  It derives the public key from the configured private key, to compare with
  what the dashboard shows or to register it again.
- **Every call fails with `401` after a deploy.** Run
  `mollie_pay:request_signing:verify`. `Refused` with a key you trust usually
  means the API key and the private key are from different pairs, for example
  production's API key with staging's private key.

## Rotating

1. Generate a new pair.
2. Create a new API key in the Mollie dashboard with the new public key.
3. Deploy the new API key and the new private key together.
4. Run `mollie_pay:request_signing:verify`.
5. Delete the old API key at Mollie.

Webhooks keep working through a rotation, as long as the new API key is for
the same website profile: Mollie sends an id, and the engine fetches the
object with whatever API key it has at that moment.

## With openssl

The generator needs nothing but the app. The same pair with `openssl`, as
files:

```sh
umask 077
openssl genpkey -algorithm Ed25519 -out ed25519_private.pem
openssl pkey -in ed25519_private.pem -pubout -out ed25519_public.pem
```

Paste `ed25519_public.pem` into Mollie, store the contents of
`ed25519_private.pem` as the secret, and delete both files. The PEM file's
contents are accepted as they are.

## In tests

A host app's tests need no key. With a key set and WebMock in use, the
stubbed requests carry `X-Client-Signature` and `X-Client-Signed-At`, so a
test can assert on them:

```ruby
MolliePay.configuration.request_signing_key = OpenSSL::PKey.generate_key("ED25519").private_to_pem
```

## For engine development

`bin/e2e-request-signing` in this repository runs against Mollie's real API
with a test API key that has a public key registered. It proves that Mollie
refuses an unsigned request, sends every kind of request the engine makes,
signed, and ends with wrongly signed requests that must be refused. The test
suite never runs it; its header says how to run it.
