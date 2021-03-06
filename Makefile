ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

all: busybox
.PHONY: disks

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
	sed -i -- 's/# CONFIG_DEBUG_KERNEL is not set/CONFIG_DEBUG_KERNEL=y/' $(ROOT_DIR)/obj/linux/.config
	sed -i -- 's/# CONFIG_BTRFS_FS is not set/CONFIG_BTRFS_FS=y/' $(ROOT_DIR)/obj/linux/.config
	sed -i -- 's/# CONFIG_OVERLAY_FS is not set/CONFIG_OVERLAY_FS=y/' $(ROOT_DIR)/obj/linux/.config
	sed -i -- 's/CONFIG_IPV6=y/# CONFIG_IPV6 is not set/' $(ROOT_DIR)/obj/linux/.config
	cd src/busybox && make O=$(ROOT_DIR)/obj/busybox defconfig
	sed -i -- 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' $(ROOT_DIR)/obj/busybox/.config

images: busybox-image alpine-image debian-image

gdb:
	gdb obj/linux/vmlinux

create-disks: disks/ext4.img disks/btrfs.img

disks: create-disks unmount-disks

disks/btrfs.img:
	qemu-img create disks/btrfs.img 5G
	parted -s disks/btrfs.img  -- mklabel msdos
	parted -s disks/btrfs.img mkpart primary 0% 100%
	mkfs.btrfs -f disks/btrfs.img

disks/ext4.img:
	qemu-img create disks/ext4.img 5G
	parted -s disks/ext4.img -- mklabel msdos
	parted -s disks/ext4.img mkpart primary 0% 100%
	mkfs.ext4 -F disks/ext4.img

mount-disks: create-disks
	sudo mount -o loop disks/ext4.img disks/ext4
	sudo mount -o loop disks/btrfs.img disks/btrfs

unmount-disks:
	sudo umount disks/ext4 || true
	sudo umount disks/btrfs || true

linux: disks
	cd obj/linux && make -j3 bzImage

linux-all:
	cd obj/linux && make -j3

alpine: $(ROOT_DIR)/obj/alpine.cpio.gz linux
	qemu-system-x86_64 -kernel obj/linux/arch/x86_64/boot/bzImage -initrd obj/alpine.cpio.gz -net nic -net user -cpu host -m 1024M -smp 4 -nographic -append "console=ttyS0 init=/init raid=noautodetect" -enable-kvm -s -hda disks/ext4.img -hdb disks/btrfs.img

$(ROOT_DIR)/obj/alpine.cpio.gz:
	mkdir -p obj/alpine
	wget -nc http://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/alpine-minirootfs-3.6.2-x86_64.tar.gz -O obj/alpine-minirootfs-3.6.2-x86_64.tar.gz || true
	cd obj && sudo tar -xpf alpine-minirootfs-3.6.2-x86_64.tar.gz -C alpine
	sudo chown -R $(shell id -u):$(shell id -g) obj
	cp -av boot/init obj/alpine
	bash -c 'echo "auto lo" > obj/alpine/etc/network/interfaces'
	bash -c 'echo "iface lo inet loopback" >> obj/alpine/etc/network/interfaces'
	bash -c 'echo "auto eth0" >> obj/alpine/etc/network/interfaces'
	bash -c 'echo "iface eth0 inet dhcp" >> obj/alpine/etc/network/interfaces'
	mkdir -p obj/alpine/usr/share/udhcpc
	cp boot/udhcpc-default.script obj/alpine/usr/share/udhcpc/default.script
	cd obj/alpine && sudo find . -print0 | cpio --null -ov -R 0:0 --format=newc | gzip -9 > $(ROOT_DIR)/obj/alpine.cpio.gz

busybox: $(ROOT_DIR)/obj/busybox.cpio.gz linux
	qemu-system-x86_64 -kernel obj/linux/arch/x86_64/boot/bzImage -initrd obj/busybox.cpio.gz -net nic -net user -cpu host -m 1024M -smp 4 -nographic -append "console=ttyS0 init=/init raid=noautodetect" -enable-kvm -s -hda disks/ext4.img -hdb disks/btrfs.img

$(ROOT_DIR)/obj/busybox.cpio.gz:
	mkdir -p obj/busybox
	cd obj/busybox && make -j3 && make install
	mkdir -pv initramfs/busybox/{bin,sbin,etc,proc,sys,tmp,usr/{bin,sbin}}
	cp -av obj/busybox/_install/* initramfs/busybox
	cp -av boot/init initramfs/busybox
	mkdir -p initramfs/busybox/etc/network
	bash -c 'echo "auto lo" > initramfs/busybox/etc/network/interfaces'
	bash -c 'echo "iface lo inet loopback" >> initramfs/busybox/etc/network/interfaces'
	bash -c 'echo "auto eth0" >> initramfs/busybox/etc/network/interfaces'
	bash -c 'echo "iface eth0 inet dhcp" >> initramfs/busybox/etc/network/interfaces'
	mkdir -p initramfs/busybox/usr/share/udhcpc
	cp boot/udhcpc-default.script initramfs/busybox/usr/share/udhcpc/default.script
	cd initramfs/busybox && find . -print0 | cpio --null -ov -R 0:0 --format=newc | gzip -9 > $(ROOT_DIR)/obj/busybox.cpio.gz

debian: debian-image linux
	qemu-system-x86_64 -kernel obj/linux/arch/x86_64/boot/bzImage -hda obj/debian.img -net nic -net user -cpu host -m 1024M -smp 4 -nographic -append "console=ttyS0 root=/dev/sda rw rootfstype=ext4 init=/init raid=noautodetect" -enable-kvm -s

debian-image-init:
	dd if=/dev/zero of=obj/debian.img bs=1G count=5
	mkfs.ext4 obj/debian.img

debian-image: debian-image-clean debian-image-init
	mkdir -p obj/debian-base
	sudo mount -o loop obj/debian.img obj/debian-base
	sudo debootstrap --arch=amd64 --variant=minbase --include=ifupdown,net-tools,dhcpcd5 sid obj/debian-base
	sudo cp boot/init obj/debian-base
	sudo cp /etc/resolv.conf obj/debian-base/etc/
	sudo mkdir -p obj/debian-base/etc/network/interfaces.d
	sudo bash -c 'echo "iface eth0 inet dhcp" > obj/debian-base/etc/network/interfaces.d/eth0'
	sudo umount obj/debian-base
	sudo rmdir obj/debian-base

debian-image-clean:
	sudo umount obj/debian-base; sudo rm -rf obj/debian-base; rm obj/debian.img || true

clean: debian-image-clean
