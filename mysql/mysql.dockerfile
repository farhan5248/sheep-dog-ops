FROM mysql:9.1.0
LABEL "maintainer"=farhan.sheikh.5248@gmail.com
COPY bootstrap.sh /docker-entrypoint-initdb.d
