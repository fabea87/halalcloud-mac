# The Halal Cloud Open API, as used by the clients

This document records what the Windows client actually does, so the macOS
client can stay byte-compatible with it. It is derived from
`HccApi.cpp`, `HccProtocolWrappers.cpp` and the Playground session code in
[`halalcloud/halalcloud-client`](https://github.com/halalcloud/halalcloud-client).

## Endpoint

```
POST https://openapi.2dland.cn/<api path>
Content-Type: application/json; charset=utf-8
```

There is exactly one transport call (`HccRpcPostRequest`); every operation is a
JSON POST to a path. Responses are JSON. HTTP status codes map to gRPC-style
status codes:

| HTTP | status |
| --- | --- |
| 200 | OK (0) |
| 400 | INVALID_ARGUMENT (3) |
| 401 | UNAUTHENTICATED (16) |
| 403 | PERMISSION_DENIED (7) |
| 404 | NOT_FOUND (5) |
| 409 | ALREADY_EXISTS (6) |
| 429 | RESOURCE_EXHAUSTED (8) |
| 499 | CANCELLED (1) |
| 500 | UNKNOWN (2) |
| 501 | UNIMPLEMENTED (12) |
| 503 | UNAVAILABLE (14) |
| 504 | DEADLINE_EXCEEDED (4) |

## Request signing: `HL6-HMAC-SHA256`

Constants (identical in `HccApi.cpp`):

```
secret id      puc_5_dcpqfdvu8qnt_v1
secret key     c8303e83dc164352a38289409681df8d
key prefix     HL6
scope suffix   hl6_request
```

Headers that are signed (always this set, always in this order):

```
content-type: application/json; charset=utf-8
host: openapi.2dland.cn
x-hl-nonce: <GUID form of 16 random bytes>
x-hl-timestamp: <UTC, yyyy-MM-ddTHH:mm:ssZ>
```

`host` is part of the signature but is not sent: the HTTP stack fills it in
from the URL.

Canonical request (note the empty line before the signed-header list):

```
POST\n
<api path>\n
\n
content-type:<value>\n
host:openapi.2dland.cn\n
x-hl-nonce:<nonce>\n
x-hl-timestamp:<timestamp>\n
\n
content-type;host;x-hl-nonce;x-hl-timestamp\n
<lowercase hex SHA-256 of the exact request body bytes>
```

String to sign:

```
HL6-HMAC-SHA256\n
<timestamp>\n
<yyyy-MM-dd>/<access token>/hl6_request\n
<lowercase hex SHA-256 of the canonical request>
```

Signature key:

```
key = HMAC("HL6" + secret key, yyyy-MM-dd)
key = HMAC(key, access token)
key = HMAC(key, "hl6_request")
key = HMAC(key, string to sign)
signature = lowercase hex(key)
```

`Authorization` header (no spaces after the commas):

```
HL6-HMAC-SHA256 Credential=puc_5_dcpqfdvu8qnt_v1/<yyyy-MM-dd>/<access token>/hl6_request,SignedHeaders=content-type;host;x-hl-nonce;x-hl-timestamp,Signature=<signature>
```

Requests that do not need a session use the literal access token `*`
(e.g. `/v6/oauth/authorize`), which then appears in the credential scope.

A test vector for the Swift implementation is in
`Tests/HalalCloudCoreTests/HalalCloudCoreTests.swift`.

## Sign-in (PKCE, "legacy" mode)

| Path | Body | Response |
| --- | --- | --- |
| `/v6/oauth/authorize` | `client_id`, `code_challenge` (base64url SHA-256 of the verifier), `code_challenge_method: "S256"`, `legacy: true` | `code`, `redirect_uri` |
| `/v6/oauth/get_authorize_state` | `code` | `status` |
| `/v6/oauth/get_token` | `code`, `code_verifier` | `access_token`, `refresh_token` |
| `/v6/oauth/refresh_token` | `refresh_token` | `access_token`, `refresh_token` |
| `/v6/user/logoff` | `access_token`, `refresh_token` | — |

The verifier is 32 random bytes encoded as base64url without padding. The
client polls `get_authorize_state` every 200 ms and treats
`AUTHORIZATION_TOKEN_CREATED` as success, `AUTHORIZATION_SUCCESS` as success,
and anything else as pending; unknown values mean the request expired and must
be restarted.

The returned `redirect_uri` is what the user opens (browser) or scans (QR
code). The Windows client renders it as a QR code, so it is a URL that the
mobile app understands.

On `UNAUTHENTICATED`, requests are retried once after `refresh_token` succeeds.
The refresh token is persisted; the access token is not.

## Account and files

| Path | Body | Response |
| --- | --- | --- |
| `/v6/user/get` | `{}` | `identity`, `name`, `icon` |
| `/v6/user/get_statistics_and_quota` | `{}` | `disk_statistics_quota.bytes_quota`, `.bytes_used` |
| `/v6/userfile/list` | `parent.path`, `list_info.token` | `files[]`, `list_info.token` |
| `/v6/userfile/get` | `path` | one file object |
| `/v6/userfile/create` | `path` | — |
| `/v6/userfile/list_recent_updated_files` | `parent.path`, `start_ts`, `contain_subdir`, `contain_self` | `files[]` with `path`, `update_ts`, `deleted` |

A file object has `name`, `size`, `dir`, `hidden`, `create_ts`, `update_ts`,
`content_identity`. Timestamps are milliseconds since the epoch. Pagination
continues while `list_info.token` is non-empty.

Numbers may arrive as JSON numbers or as JSON strings; both clients coerce
through a string representation.

## Downloading a file

1. `/v6/userfile/parse_file_slice` with `path` returns:

   ```
   file_size, content_identity, store_type,
   raw_nodes: ["bafkrei…", …],
   sizes: [{ "start_index": 0, "end_index": 12287, "size": 524288 }, …]
   ```

   `sizes` groups consecutive nodes that share a block size. Concatenating all
   nodes in order gives the file; the total must equal `file_size`.

2. `/v6/userfile/get_slice_download_address` with `version: 1` and up to 200
   `identity` values per call returns
   `addresses: [{ "identity", "download_address", "encrypt" }]`.

3. `GET download_address` (follow redirects) for the exact byte length of the
   block, then XOR every byte with `encrypt` (a no-op when 0).

4. Verify the plaintext: a Halal Cloud CID is

   ```
   base32(0x01 0x55 0x12 0x20 || sha256 <32 bytes>)   prefixed with "b"
   ```

   (59 characters). `0x01` = CIDv1, `0x55` = IPLD raw, `0x12` = SHA2-256,
   `0x20` = digest length. Files stored in Baidu Object Storage
   (`store_type == 10`) have no CID; their blocks can only be size-checked.

Blocks are immutable, so they are cached on disk by identifier (the Windows
client uses `BlocksCache/` under its data directory; this client uses
`~/Library/Caches/HalalCloud/Blocks`).

## Local state

The Windows client keeps `<data>/Profiles/Default/Profile.json`:

```json
{ "RefreshToken": "…", "MountPoint": "Z:" }
```

This client keeps the same file (without `MountPoint`) under
`~/Library/Application Support/HalalCloud/Profiles/Default/Profile.json`, with
`0600` permissions, so an existing Windows profile directory can be copied
across.

## Not implemented upstream

- Upload: `/v6/userfile/create_upload_token` returns Baidu Object Storage
  credentials, and the actual PUT (`HccBcePutObject`) is commented out.
- FUSE `read`: the Windows `ReadCallback` returns 0 bytes; only `getattr`,
  `readdir` and `statfs` are real, i.e. the mounted volume lists names but does
  not serve file content.
