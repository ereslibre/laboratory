ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

all: run-debian

init:
	@echo "* Please, link your linux kernel sources to src/linux"
	@echo "  $$ ln -sf ~/my-linux-sources src/linux"
	@echo "      (or)"
	@echo "  $$ git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
	@echo "* Please, link your busybox sources to src/busybox"
	@echo "  $$ ln -sf ~/my-busybox-sources src/busybox"
	@echo "      (or)"
	@echo "  $$ git clone git://busybox.net/busybox.git"
	mkdir -p obj/linux obj/busybox
	cd src/linux && make O=$(ROOT_DIR)/obj/linux x86_64_defconfig
	cd src/linux && make O=$(ROOT_DIR)/obj/linux kvmconfig
	cd src/busybox && make O=$(ROOT_DIR)/obj/busybox defconfig
	echo "CONFIG_STATIC=y" >> $(ROOT_DIR)/obj/busybox/.config

run-busybox:
	qemu-system-x86_64 -kernel obj/linux/arch/x86_64/boot/bzImage -initrd obj/initramfs.cpio.gz -net nic -net user -m 1024M -smp 2 -nographic -append "console=ttyS0"

busybox:
	mkdir -p obj/busybox
	cd obj/busybox && make -j4 && make install

busybox-image: busybox
	mkdir -pv initramfs/busybox/{bin,sbin,etc,proc,sys,tmp,usr/{bin,sbin}}
	cp -av obj/busybox/_install/* initramfs/busybox
	cp -av boot/init initramfs/busybox
	cd initramfs/busybox && find . -print0 | cpio --null -ov -R 0:0 --format=newc | gzip -9 > $(ROOT_DIR)/obj/initramfs.cpio.gz

linux:
	cd obj/linux && make -j4

run-debian:
	qemu-system-x86_64 -kernel obj/linux/arch/x86_64/boot/bzImage -hda debian.img -net nic -net user -m 1024M -smp 2 -nographic -append "console=ttyS0 root=/dev/sda init=/init rw"

run-debian-curses:
	qemu-system-x86_64 -curses -kernel obj/linux/arch/x86_64/boot/bzImage -hda debian.img -net nic -net user -m 1024M -smp 2 -append "root=/dev/sda rw"

run-debian-graphical:
	qemu-system-x86_64 -kernel obj/linux/arch/x86_64/boot/bzImage -hda debian.img -net nic -net user -m 1024M -smp 2 -append "root=/dev/sda rw"

debian-disk-init:
	dd if=/dev/zero of=debian.img bs=1G count=5
	mkfs.ext3 debian.img

debian-disk: debian-disk-clean debian-disk-init
	mkdir -p debian-base
	sudo mount -o loop debian.img debian-base
	sudo debootstrap --variant=minbase --include=sysvinit-core,ifupdown,net-tools,dhcpcd5 sid debian-base
	sudo cp boot/init debian-base
	sudo cp /etc/resolv.conf debian-base/etc/
	sudo mkdir -p debian-base/etc/network/interfaces.d
	sudo bash -c 'echo "iface eth0 inet dhcp" > debian-base/etc/network/interfaces.d/eth0'
	sudo bash -c 'echo "net.ipv6.conf.all.disable_ipv6 = 1" >> debian-base/etc/sysctl.conf'
	sudo bash -c 'echo "net.ipv6.conf.default.disable_ipv6 = 1" >> debian-base/etc/sysctl.conf'
	sudo bash -c 'echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> debian-base/etc/sysctl.conf'
	sudo umount debian-base/proc debian-base/dev debian-base/sys debian-base/tmp debian-base
	sudo rmdir debian-base

debian-disk-clean:
	sudo umount debian-base/proc debian-base/dev debian-base/sys debian-base/tmp debian-base || true
	sudo umount debian-base; sudo rm -rf debian-base; rm debian.img || true

clean: debian-disk-clean
