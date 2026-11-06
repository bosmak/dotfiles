#!/usr/bin/env sh
sleep 10 && /usr/bin/flatpak run --branch=stable --arch=x86_64 --command=karere --file-forwarding io.github.tobagin.karere @@u %U @@
