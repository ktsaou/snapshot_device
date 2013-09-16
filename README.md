snapshot_device
===============

Create snapshot devices for any file or device in linux


Usage

---------------------------------------------------------------------

To create a snapshot of a device or a file:

```sh
./snapshot_device.sh name size file device
```

        name    the name of the NEW snapshot device to create

        size    the size in MB, of the snapshot to create
                this need to be as big you like. If it fills up, the
                snapshot device will start returning errors, but no
                harm will be made to your original data; just remove
                the snapshot, create a bigger and retry

        file    the filename to save the NEW snapshot data
                this file will be created as sparce file, so that
                its size will be allocated only as the snapshot grows

        device  the EXISTING device with the original data
                this can also be a regular file, in which case a
                loop device will be created to map it to a device

---------------------------------------------------------------------

To remove the created snapshot:

```sh
./snapshot_device.sh remove name
```

        remove  just the word 'remove'
        name    the name of the snapshot to remove

---------------------------------------------------------------------

To merge the data from the created snapshot changes back to the
original device:

```sh
./snapshot_device.sh merge name
```

        merge   just the word 'merge'
        name    the name of the snapshot to merge

---------------------------------------------------------------------

To list the created snapshots:

```sh
./snapshot_device.sh ls
```

        ls      just the word 'ls'

---------------------------------------------------------------------

