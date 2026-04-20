# WARNING — read before rebuilding.
#
# Docker Hub repushes mutable tags like `mysql:9.1.0` with new layers over
# time. The `mysql:9.1.0` image that existed 10 months ago (when the
# ghcr.io/farhan5248/sheep-dog-dev-db:latest image was last built and found
# to work) is NOT the same as the one you'd get from `docker pull mysql:9.1.0`
# today — the layer digests differ completely. A rebuild from the current
# (pinned) digest below has been observed to produce a broken image where
# the MySQL entrypoint skips init, leaving `root` and `mbt` users
# unconfigured and downstream Spring services failing at startup with
# Hibernate "Unable to determine Dialect" errors on prod EKS deploys.
#
# The pinned digest below is recorded for reproducibility — so we know
# exactly what we're pointing at when we hit the next incident. It is NOT
# known to produce a working image. Until the rebuild regression is root-
# caused and fixed:
#
#   - Do NOT rebuild this image on a whim.
#   - The known-working image lives on ghcr.io/farhan5248/sheep-dog-dev-db
#     at digest sha256:b4312ce47618cc2b41ca99fa966782cb2f206e6e39f1f1a91746aa66cfe62443
#     and on nexus-docker.sheepdog.io/sheep-dog-dev-db:latest (mirrored).
#   - If you do rebuild, test first_init on an EKS cluster (or a fresh
#     minikube PVC) BEFORE pushing over :latest. `mysql -u mbt -pmbt -e
#     "SHOW DATABASES"` inside the resulting pod must succeed.
#
# See the discussion on #233 for the full root-cause chain that surfaced
# this.
FROM mysql:9.1.0@sha256:0255b469f0135a0236d672d60e3154ae2f4538b146744966d96440318cc822c6
LABEL "maintainer"=farhan.sheikh.5248@gmail.com
COPY bootstrap.sh /docker-entrypoint-initdb.d
