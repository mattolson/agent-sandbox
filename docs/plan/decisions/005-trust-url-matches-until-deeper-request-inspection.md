# 005: Trust URL Matches Until Deeper Request Inspection Exists

## Status

Accepted

## Context

`m14` extends proxy policy from host-only allowlists to request-aware URL matching on method, path, and query
parameters. During planning, a valid question came up: if the security concern is data exfiltration to allowed hosts,
should `m14` also constrain headers?

Headers are a real exfiltration surface, but they are not the whole story. Request bodies are also part of the outbound
payload. If `m14` were to treat headers as mandatory for exfiltration control while ignoring bodies, the boundary would
be arbitrary and misleading.

At the same time, requiring full request inspection immediately would make `m14` much larger and blur the line between:

- URL-shape restriction on trusted endpoints
- deeper outbound content inspection

We need an explicit statement of what a matched URL rule means today, so users are not given a false sense that
`method + path + query` fully solves exfiltration risk on allowed endpoints.

## Decision

For `m14`, matching a URL rule implies that the matched endpoint is trusted to receive the full request.

That means:

- `m14` policy will constrain URL shape via host, method, path, and query
- `m14` will not inspect or constrain request headers
- `m14` will not inspect or constrain request bodies
- header and request-body analysis are explicitly deferred to future work

The intended future direction is that deeper request inspection may allow users to widen the set of allowed endpoints
while still keeping outbound traffic bounded by stronger content-aware rules.

## Rationale

- It keeps `m14` focused on URL-shape control instead of turning it into a full outbound content inspection milestone.
- It avoids a misleading half-measure where headers are treated as the important exfiltration surface while request
  bodies remain unrestricted.
- It matches the current project plan, which already scopes `m14` around method, path, and query filtering.
- It creates a clear trust boundary: URL matching narrows *where* requests may go; deeper inspection is future work for
  narrowing *what* may be sent there.

## Consequences

**Positive:**
- `m14` stays implementable and reviewable as a request-shape milestone.
- Policy semantics remain clear: a matched URL rule is a trust decision about that endpoint.
- Future header/body inspection can be added deliberately instead of being smuggled into `m14` piecemeal.

**Negative:**
- `m14` does not fully address exfiltration risk on otherwise-allowed endpoints.
- Users must understand that allowing a URL today implicitly trusts the endpoint with the request payload, not just the
  URL itself.
- Some endpoints that are too broad to trust today may remain blocked until deeper inspection exists.

## Follow-up

- Document this trust assumption in the `m14` milestone and task plans.
- Keep header matching and request-body analysis out of `m14.1`.
- Revisit deeper inspection in a future milestone once there is a clear policy model for headers and bodies.
