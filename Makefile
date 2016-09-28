all: run-debian-systemd

run-busybox:
	qemu-system-x86_64 -kernel obj/linux/arch/x86_64/boot/bzImage -initrd obj/initramfs.cpio.gz -net nic -net user -m 1024M -smp 2 -nographic -append "console=ttyS0"

busybox:
	cd obj/busybox && make install

busybox-image: busybox
	mkdir -pv initramfs/busybox/{bin,sbin,etc,proc,sys,usr/{bin,sbin}}
	cp -av obj/busybox/_install/* initramfs/busybox
	cp -av initramfs/init initramfs/busybox
	cd initramfs/busybox && find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../../obj/initramfs.cpio.gz

linux:
	cd obj/linux && make -j4

run-debian:
	qemu-system-x86_64 -kernel obj/linux/arch/x86_64/boot/bzImage -hda debian.img -net nic -net user -m 1024M -smp 2 -nographic -append "console=ttyS0 root=/dev/sda rw"

run-debian-curses:
	qemu-system-x86_64 -curses -kernel obj/linux/arch/x86_64/boot/bzImage -hda debian.img -net nic -net user -m 1024M -smp 2 -append "root=/dev/sda rw"

run-debian-graphical:
	qemu-system-x86_64 -kernel obj/linux/arch/x86_64/boot/bzImage -hda debian.img -net nic -net user -m 1024M -smp 2 -append "root=/dev/sda rw"

run-debian-systemd:
	qemu-system-x86_64 -kernel obj/linux/arch/x86_64/boot/bzImage -hda debian-systemd.img -net nic -net user -m 1024M -smp 2 -nographic -append "console=ttyS0 root=/dev/sda rw"

run-debian-systemd-curses:
	qemu-system-x86_64 -curses -kernel obj/linux/arch/x86_64/boot/bzImage -hda debian-systemd.img -net nic -net user -m 1024M -smp 2 -append "root=/dev/sda rw"

run-debian-systemd-graphical:
	qemu-system-x86_64 -kernel obj/linux/arch/x86_64/boot/bzImage -hda debian-systemd.img -net nic -net user -m 1024M -smp 2 -append "root=/dev/sda rw"

debian-disks: debian-disk debian-systemd-disk

debian-disk-init:
	dd if=/dev/zero of=debian.img bs=1G count=5
	mkfs.ext3 debian.img

debian-disk: debian-disk-clean debian-disk-init
	mkdir -p debian-base
	sudo mount -o loop debian.img debian-base
	sudo debootstrap --variant=minbase --include=sysvinit-core,ifupdown,net-tools,isc-dhcp-client sid debian-base
	sudo mount -o bind /proc debian-base/proc
	sudo mount -o bind /dev debian-base/dev
	sudo mount -o bind /sys debian-base/sys
	sudo mount -t tmpfs none debian-base/tmp
	sudo cp /etc/resolv.conf debian-base/etc/
	sudo mkdir -p debian-base/etc/network/interfaces.d
	sudo bash -c 'echo "iface eth0 inet dhcp" > debian-base/etc/network/interfaces.d/eth0'
	sudo bash -c 'echo "net.ipv6.conf.all.disable_ipv6 = 1" >> debian-base/etc/sysctl.conf'
	sudo bash -c 'echo "net.ipv6.conf.default.disable_ipv6 = 1" >> debian-base/etc/sysctl.conf'
	sudo bash -c 'echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> debian-base/etc/sysctl.conf'
	sudo bash -c 'echo "T0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100" >> debian-base/etc/inittab'
	sudo chroot debian-base /bin/bash -c "passwd -d root"
	sudo umount debian-base/proc debian-base/dev debian-base/sys debian-base/tmp debian-base
	sudo rmdir debian-base

debian-disk-clean:
	sudo umount debian-base/proc debian-base/dev debian-base/sys debian-base/tmp debian-base || true
	sudo umount debian-base; sudo rm -rf debian-base; rm debian.img || true

debian-systemd-disk-init:
	dd if=/dev/zero of=debian-systemd.img bs=1G count=5
	mkfs.ext3 debian-systemd.img

debian-systemd-disk: debian-systemd-disk-clean debian-systemd-disk-init
	mkdir -p debian-systemd-base
	sudo mount -o loop debian-systemd.img debian-systemd-base
	sudo debootstrap --variant=minbase --include=systemd-sysv,ifupdown,net-tools,isc-dhcp-client sid debian-systemd-base
	sudo mount -o bind /proc debian-systemd-base/proc
	sudo mount -o bind /dev debian-systemd-base/dev
	sudo mount -o bind /sys debian-systemd-base/sys
	sudo mount -t tmpfs none debian-systemd-base/tmp
	sudo cp /etc/resolv.conf debian-systemd-base/etc/
	sudo mkdir -p debian-systemd-base/etc/network/interfaces.d
	sudo bash -c 'echo "iface eth0 inet dhcp" > debian-systemd-base/etc/network/interfaces.d/eth0'
	sudo bash -c 'echo "net.ipv6.conf.all.disable_ipv6 = 1" >> debian-systemd-base/etc/sysctl.conf'
	sudo bash -c 'echo "net.ipv6.conf.default.disable_ipv6 = 1" >> debian-systemd-base/etc/sysctl.conf'
	sudo bash -c 'echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> debian-systemd-base/etc/sysctl.conf'
	sudo chroot debian-systemd-base /bin/bash -c "passwd -d root"
	sudo chroot debian-systemd-base /bin/bash -c "systemctl enable getty@ttyS0.service"
	sudo umount debian-systemd-base/proc debian-systemd-base/dev debian-systemd-base/sys debian-systemd-base/tmp debian-systemd-base
	sudo rmdir debian-systemd-base

debian-systemd-disk-clean:
	sudo umount debian-systemd-base/proc debian-systemd-base/dev debian-systemd-base/sys debian-systemd-base/tmp debian-systemd-base || true
	sudo umount debian-systemd-base; sudo rm -rf debian-systemd-base; rm debian-systemd.img || true

clean: debian-systemd-disk-clean debian-disk-clean
