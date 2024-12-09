# ACRadio

A bash script that lets you play music and rain ambience in the style of a
certain well-known town management game. 

## Requirements
- mpv

## Setup
In order to use the script, you will need to find mp3 files for the background
music and rain ambience. Due to licensing and copyright, I can not do this for
you. Game BGM files should be numbered 00.mp3 through 23.mp3 (one for each hour).
These files should be placed in a folder within the cloned repository, and your
config file should point to that folder with the "GAME" variable. 
For ambience, create the directory `ambience` within the cloned repository, and
add an mp3 of your favorite rain background noise to it. Ideally one that loops
cleanly. 

## Config

You will need to create a config file at `$HOME/.config/acradio`. This config
file should contain the following required parameters:
```bash
GAME="game_music_folder_name"
```

The following additional parameters are optional:
```bash
ENABLE_RAIN=1 # 0 or 1
AUTO_RAIN=0 # 0 or 1, conflicts with ENABLE_RAIN
MUSIC_VOLUME=65 # any int between 0 and 100
RAIN_VOLUME=35 # any int between 0 and 100
AUTO_RAIN_LOC="mytown" # any location / code you can pass to wttr.in, url fmt
```


