# CLI image - build context should be project root to access .git

FROM alpine:3 AS builder

RUN apk add --update --no-cache git

WORKDIR /build
COPY .git /build/.git
COPY cli /build/cli

RUN set -eux; \
	date=$(git log -n1 --date=format:%Y%m%d.%H%M%S --format=%cd); \
	sha=$(git describe --abbrev=7 --dirty --always --tags); \
	echo "$date-$sha" > cli/.version; \
	cat cli/.version

FROM docker:29-cli

RUN apk add --update --no-cache bash yq ncurses

WORKDIR /app
ENTRYPOINT ["/opt/agentbox/bin/agentbox"]

COPY --from=builder /build/cli /opt/agentbox
