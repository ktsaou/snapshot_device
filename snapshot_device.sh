#!/bin/sh

me="$0"
sectorsize=512
loop4real=0
snapname=
snaploop=
snapsize=
snapfile=
realdevice=
origindevice=
snaptype=
snapsize=

usage() {
cat <<USAGEEND

---------------------------------------------------------------------

To create a snapshot of a device or a file:

$me name size file device

	name	the name of the NEW snapshot device to create
		
	size	the size in MB, of the snapshot to create
		this need to be as big you like. If it fills up, the
		snapshot device will start returning errors, but no
		harm will be made to your original data; just remove
		the snapshot, create a bigger and retry
		
	file	the filename to save the NEW snapshot data
		this file will be created as sparce file, so that
		its size will be allocated only as the snapshot grows
	
	device	the EXISTING device with the original data
		this can also be a regular file, in which case a
		loop device will be created to map it to a device

---------------------------------------------------------------------

To remove the created snapshot:

$me remove name
	
	remove	just the word 'remove'
	name	the name of the snapshot to remove

---------------------------------------------------------------------

To merge the data from the created snapshot changes back to the
original device:

$me merge name
	
	merge	just the word 'merge'
	name	the name of the snapshot to merge

---------------------------------------------------------------------

To list the created snapshots:

$me ls
	
	ls	just the word 'ls'

---------------------------------------------------------------------

USAGEEND
exit 1
}

run="/run"
test ! -d "$run" && run="/var/run"
test ! -d "$run" && run="/tmp"
test ! -d "$run" && run="/var/tmp"
test ! -d "$run" && run="/"
run="$run/snapshots"

if [ ! -d "$run" ]
then
	echo "Snapshots will be saved in '$run'."
	mkdir -p "$run" || exit 1
	chown root:root "$run"
	chmod 0770 "$run"
fi

if [ -z "$1" -o "z$1" = "z--help" -o "z$1" = "z-h" ]
then
	usage
	exit 1
fi

save_snapshot() {
	cat >"$run/$snapname.snapshot" <<INFO
#!/bin/sh
snapname="$snapname"
snaploop="$snaploop"
snapfile="$snapfile"
realdevice="$realdevice"
origindevice="$origindevice"
loop4real=$loop4real
sectorsize=$sectorsize
sectors=$sectors
snaptype="$snaptype"
snapsize="$snapsize"
INFO
	chown root:root "$run/$snapname.snapshot"
	chmod 0660 "$run/$snapname.snapshot"
}

load_snapshot() {
	if [ ! -f "$run/$1.snapshot" ]
	then
		echo >&2 "The is no snapshot named '$1'."
		exit 1
	fi
	
	snapname=
	snaploop=
	snapfile=
	realdevice=
	origindevice=
	loop4real=
	sectorsize=
	sectors=
	snaptype=
	snapsize=
	
	# echo "Loading snapshot '$1'..."
	source "$run/$1.snapshot" || exit 1
	
	test -z "$snaptype" && snaptype="`dmsetup status "$snapname" | cut -d ' ' -f 3`"
	test -z "$sectors" && sectors="`blockdev --getsz "$realdevice"`"
	
	return 0
}

print_size() {
	local bytes="$1"
	
	if [ $bytes -ge $((10 * 1024 * 1024 * 1024)) ]
	then
		local unit=$((1 * 1024 * 1024 * 1024))
		local label="GB"
	elif [ $bytes -ge $((10 * 1024 * 1024)) ]
	then
		local unit=$((1 * 1024 * 1024))
		local label="MB"
	elif [ $bytes -ge $((10 * 1024)) ]
	then
		local unit=$((1 * 1024))
		local label="KB"
	else
		local unit=1
		local label="B"
	fi
	
	echo "$((bytes / unit)) $label"
}

snapshot_status() {
	local start="$1"
	local size="$2"
	local type="$3"
	local usage="$4"
	local metadata="$5"
	
	case "$type" in 
		snapshot|snapshot-merge)
			if [ "$usage" = "Invalid" ]
			then
				echo "INVALID"
			else
				local total=`echo $usage | cut -d '/' -f 2`
				local used=`echo $usage | cut -d '/' -f 1`
				local data=$((used - metadata))
				
				local totalb=$((total * sectorsize))
				local usedb=$((used * sectorsize))
				local datab=$((data * sectorsize))
				local metab=$((metadata * sectorsize))
				
				local usedpc=$((used * 100 / total))
				local datapc=$((data * 100 / total))
				local metapc=$((meta * 100 / total))
				
				echo "$usedpc% full (size `print_size $totalb`, usage: `print_size $datab` in data, `print_size $metab` in metadata)"
			fi
			;;
		
		*)
			echo "UNKNOWN type '$type'"
			;;
	esac
}

if [ "$1" = "ls" ]
then
	echo "These are the currently running snapshots:"
	echo
	cd "$run" || exit 1
	ls | while read name
	do
		n=`echo "$name" | sed "s/\.snapshot$//g"`
		load_snapshot "$n" || continue
		
		printf "$snapname ($snaptype): "
		snapshot_status `dmsetup status "$snapname" --target "$snaptype"`
	done
	echo
	exit 0
fi

remove_snapshot() {
	dmsetup remove "$snapname"
	losetup -d "$snaploop"
	# test -b "/dev/$snapname" && rm "/dev/$snapname"
	test -f "$snapfile" && rm "$snapfile"
	
	test $loop4real -eq 1 && losetup -d "$realdevice"
}

if [ "$1" = "remove" ]
then
	load_snapshot "$2" || exit 1
	
	echo "Removing snapshot '$snapname'..."
	remove_snapshot
	rm "$run/$snapname.snapshot"
	echo "OK"
	exit 0
fi

if [ "$1" = "merge" ]
then
	load_snapshot "$2" || exit 1
	
	test -z "$snaptype" && snaptype="snapshot"
	test -z "$sectors" && sectors=`blockdev --getsz "$realdevice"`
	
	if [ ! "$snaptype" = "snapshot" ]
	then
		echo >&2 "The snapshot '$snapname' is set to '$snaptype'."
		echo >&2 "For merging to work it should be set to 'snapshot'."
		exit 1
	fi
	
	echo
	echo
	echo "Are you sure you want to merge the contents of the snapshot"
	echo "'$snapname' back to the device '$origindevice'?"
	echo "If you agree all changes made to '$snapname' will be committed"
	echo "permanently back to the '$origindevice'."
	echo
	printf " DO YOU AGREE? WRITE 'COMMIT' or press CTRL-C to break > "
	read reply
	if [ ! "$reply" = "COMMIT" ]
	then
		echo "Cancelling. No changes made."
		exit 1
	fi
	
	echo "Merging data of snapshot '$snapname' back to '$origindevice'..."
	dmsetup remove "$snapname" || exit 1
	echo 0 $sectors snapshot-merge "$realdevice" "$snaploop" p $sectorsize | dmsetup create "$snapname"
	if [ ! $? -eq 0 ]
	then
		echo >&2 "Failed to create the snapshot merge."
		exit 1
	fi
	
	snaptype="snapshot-merge"
	save_snapshot
	
	exit 0
fi

snapname="$1"; shift
snapsize="$1"; shift
snapfile="$1"; shift
realdevice="$1"; shift
origindevice="$realdevice"
snaptype="snapshot"

if [ -z "$snapfile" ]
then
	usage
	exit 1
fi

snapdir=`dirname "$snapfile"`
if [ "$snapdir" = "." ]
then
	snapfile="`pwd`/$snapfile"
fi

if [ -z "$snapfile" -o -e "$snapfile" ]
then
	echo >&2 "Snapshot file '$snapfile' already exists."
	exit 1
fi

if [ -z "$realdevice" -o ! -e "$realdevice" ]
then
	echo >&2 "Real device '$realdevice' does not exist."
	exit 1
fi

if [ -z "$snapname" -o -e "/dev/mapper/$snapname" ]
then
	echo >&2 "Snapshot device '$snapname' already exists."
	exit 1
fi

expr $snasize + 1 >/dev/null 2>&1
if [ ! $? -eq 0 ]
then
	echo >&2 "Snapshot size '$snapsize' is not a number."
	exit 1
fi

if [ $snapsize -le 0 ]
then
	echo >&2 "Snapshot size '$snapsize' cannot be less or equal to zero."
	exit 1
fi

if [ ! -b "$realdevice" -a -f "$realdevice" ]
then
	echo
	echo "Origin '$realdevice' seems to be a file, not a block device."
	echo "Creating a block device out of it..."
	realdevice=`losetup --find --show "$origindevice"`
	
	if [ -z "$realdevice" ]
	then
		echo >&2 "Failed to create the device."
		exit 1
	fi
	
	loop4real=1
fi

sectors=`blockdev --getsz "$realdevice"`
echo
echo "Origin device has a size of $((sectors * 512)) bytes."
nsectors=$((sectors * 512 / sectorsize))

if [ $((sectors * 512)) -ne $((nsectors * sectorsize)) ]
then
	echo >&2
	echo >&2 "The device $origindevice cannot be mapped entirelly."
	echo >&2 "Its size is $((sectors * 512)) bytes (or $sectors sectors * 512 bytes)"
	echo >&2 "while the requested sector size is $sectorsize bytes, which"
	echo >&2 "gives $((nsectors * sectorsize)) bytes (or $nsectors sectors * $sectorsize)"
	echo >&2 "this leaves $((sectors * 512 - nsectors * sectorsize)) bytes of the origin device unmapped"
	echo >&2
	
	test $loop4real -eq 1 && losetup -d "$realdevice"
	exit 1
fi
sectors=$nsectors

snapsize=$((snapsize * 1024 * 1024))
echo
echo "Creating sparse snapshot file '$snapfile' of size '$snapsize' bytes..."
echo "This file will only occupy the physical size needed by the snapshot."
echo "Its initial physical size will be just 1 byte."
echo
dd if=/dev/zero of="$snapfile" bs=1 seek=$snapsize count=1 || exit 1

echo
echo "Mounting the snapshot file '$snapfile'."
snaploop=`losetup --find --show "$snapfile"`
if [ -z "$snaploop" ]
then
	echo >&2 "Failed to create a block device for file '$snapfile'."
	rm "$snapfile"
	test $loop4real -eq 1 && losetup -d "$realdevice"
	exit 1
fi

echo
echo "Creating the snapshot device '$snapname'..."
echo 0 $sectors snapshot "$realdevice" "$snaploop" p $sectorsize | dmsetup create "$snapname"
if [ ! $? -eq 0 ]
then
	echo >&2 "Failed to create the snapshot."
	losetup -d "$snaploop"
	rm "$snapfile"
	test $loop4real -eq 1 && losetup -d "$realdevice"
	exit 1
fi

echo
echo "SUCCESS!"

echo
echo "Creating an alias for the snapshot..."
#major=`dmsetup ls | grep "^$snapname" | cut -d '(' -f 2 | cut -d ':' -f 1`
#minor=`dmsetup ls | grep "^$snapname" | cut -d ':' -f 2 | cut -d ')' -f 1`
#mknod "/dev/$snapname" b $major $minor


save_snapshot

cat <<FINAL


ALL DONE!

-----------------------------------------------------------


Snapshot '$snapname' has been created!


IMPORTANT!

To protect your original data you should not use
'$origindevice'. Use this one instead:

	'/dev/mapper/$snapname'

All writes to this device, go to the snapshot file, instead
of '$origindevice'. The snapshot file is:

	'$snapfile'

This file is now just 1 byte big, but it can grow up to
$snapsize bytes, as data are written to '/dev/mapper/$snapname'.
If it fills up, the snapshot will be returning write errors.

To remove the snapshot, execute:

	$me remove "$snapname"

-----------------------------------------------------------

FINAL

echo "Info about the snapshot."
dmsetup info "$snapname"
