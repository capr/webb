#!/bin/bash

cd "$(dirname "$0")" || exit 1

openresty=openresty-1.15.8.2
pcre=pcre-8.43
zlib=zlib-1.2.11
openssl=openssl-1.1.1d

encrypted_session_nginx_module=0.08

download_tgz() {
    local url=$1
    local name=$2
    (
    mkdir -p src && cd src || exit 1
    [ -d $name ] && return
    wget $url.tar.gz -O $name.tar.gz
    tar xvfz $name.tar.gz
    [ -d $name ] || { echo "error downloading $name."; exit 1; }
    )
}

download() {
    download_tgz $1/$2 $2
}

download_github_release() {
    download_tgz https://github.com/$1/$2/archive/v$3 $2-$3
}

download https://openresty.org/download/ $openresty
download https://ftp.pcre.org/pub/pcre/ $pcre
download https://zlib.net/ $zlib
download https://www.openssl.org/source/ $openssl

download_github_release openresty encrypted-session-nginx-module $encrypted_session_nginx_module

mkdir -p openresty
cd src/$openresty

./configure \
    --prefix=../../openresty \
    --with-pcre=../$pcre \
    --with-pcre-jit \
    --with-zlib=../$zlib \
    --with-openssl=../$openssl
    --add-module=../encrypted-session-nginx-module

make -j2
make install
