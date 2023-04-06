set name=run
sjasmplus.exe %name%.asm --lst --lstlab
HCDisk2.exe format %name%.tap -y : open %name%.tap : bin2bas rem %name%.bin %name% 32768 : dir : exit
del %name%.bin