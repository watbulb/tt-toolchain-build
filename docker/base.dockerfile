FROM debian:latest
RUN apt-get update &&  \
    apt-get install -y \
    clang make python3 python3.11-dev bash vim git
