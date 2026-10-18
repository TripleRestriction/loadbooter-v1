all:
	nasm -f bin ./src/boot.asm -o ./bin/boot.bin
	rm -rf ./bin/disk.img 2> /dev/null
	dd if=/dev/zero of=./bin/disk.img bs=1M count=10
	dd if=./bin/boot.bin of=./bin/disk.img conv=notrunc
	dd if=./bin/bzImage of=./bin/disk.img bs=512 seek=4 conv=notrunc
clean:
	rm -f ./bin/boot.bin
	rm -f ./bin/disk.img
