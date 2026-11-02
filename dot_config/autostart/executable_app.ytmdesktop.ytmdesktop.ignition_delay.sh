#!/usr/bin/env sh
sleep 10 && /usr/bin/flatpak run --branch=stable --arch=x86_64 --command=start-ytmdesktop --file-forwarding app.ytmdesktop.ytmdesktop @@u %U @@
