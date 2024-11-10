#!/bin/bash

chmod +x ./acradio.sh
ln -s ./acradio.sh "$HOME/.local/bin/acradio"

echo "acradio added to $HOME/.local/bin"
echo "ensure $HOME/.local/bin is in your PATH"
