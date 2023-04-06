File browser/disk autorun program for ICE Felix HC computers
George Chirtoaca, george.chirtoaca(@)gmail(.)com, April 2023

The purpose of this program is to have a fast file listing, that includes hidden files and also shows the aproximate file size and file attributes using colours on screen.
File selection is possible with arrow keys, to select BASIC programs and run them, making it usefull as "run" program for auto-run on HC floppy disks. That's why it tries to be small and fast.
Reading the exact file size and file type requires opening up each file, which is slow, so it's not performed. The aproximate file size provided (rounded at 128 bytes) can be used as a hint to guess the file type.
Smaller files should be the BASIC loaders (around 256 bytes). SCREEN$ files are 7168 bytes. Larger files are code files usually. Files bigger than 64K are shown with file size in kilobytes.
Can display up to 128 files (max supported by HC BASIC file system), grouped in up to 3 pages, 44 files per page. Most disks will have one page listing, quickly showing up all disk info on one screen.
System calls are kept at minimum, because are slow. The aproximate file size is determined by processing all file dir entries and summing up the record count instead of calling the system call for file size determination.
Free space is determined by summing up file sizes on disk and substracting from maximum possible size (636KB). This allows showing up the ocupied space too, that the ROM doesn't list.
Another way to determine space would be to make the system call to get disk the allocation bitmap, but that bitmap is in "phantom RAM" (IF1 paged RAM) so it's more convoluted to read and process it (count set bits).
The disk directory sectors are read and parsing the directory is done manually, because is faster and requires less code than using system calls. Catalog processing time reduced from 5 to 3 seconds!
Mathematical operations like multiplication and division are performed using bit shifts, since involve numbers that are power of 2. Again this is for having simple and small code.
Printing the text uses the BASIC ROM routine, that supports embedded color codes. The IF1 print routine doesn't support that. Direct screen output would be another way, but requires more code. Graphical output (64 columns) was excluded for the same reason.
ROM printing routing has an issue with line 21 (out of 0-23), so a trick is used to avoid scrolling: channel 0 is used for the stats printing, then lines 0-21 are printed on channel 2, also poking a variable to prevent scrolling.
The disk drive being displayed is the current drive, so the program should work as expected when executed from drive B:, as it doesn't hard code A:. A: is assumed when there's no current drive (like when loading from tape).
What was used to develop this program: 
 - SjASMPlus v1.18.2 cross-assembler
 - Crimson Editor for editing, launching assembler, deploying in emulator
 - HC 2000 Emulator for Sinclair Spectrum +3 by Rares Atodiresei, for using the Spectaculator emulator with HC-2000 emulation support
 - Spectaculator emulator, for using the debugger and it's other top quality features
 - Fuse emulator, version from Alex Badea, with HC-2000 emulation support, for double testing
 - HCDisk2 by myself, for creating/updating disk images for HC in DSK format.

Motivation? 
 - I wanted to refresh my Z80 assembly language
 - I wanted to create an usefull tool for HC computers, with features that don't exist yet
 - I wanted to publish the code, in case it's usefull in understanding how HC computers disk system works
I realise some people may find it useless, but it's still a good exercise for myself and others.

How it works:
1. Reads disk catalog and saves a line in a table for each file, with info from directory entry 0: file name, 128 byte record count.
2. Reads disk catalog again, to read the total record count for each file. This second pass is required because some files may have dir entry 1 show up before dir entry 0.
3. Calculates disk space used by files, based on cache table record count, rounding up to 2048 (block size).
4. Displays total used space on disk, file count, disk free space, listing page 1/2/3.
5. Displays file list and file size in bytes, rounded up at 128 bytes (CPM style). File attributes are shown in color, as noted on screen: red=read only, magenta=system (hidden from CAT), black=read only + system.