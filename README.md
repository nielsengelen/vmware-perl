# vmware-perl scripts

## Table of Contents

* [Usage](#usage-example)
* [Scripts](#scripts)
* [References](#references)

## Description

Collection of perl scripts that leverage the VMWare SDK for Perl. The scripts here are not exclusive as they are sometimes a bundle of several other scripts or snippets from other examples.

## Scripts

* deploy-template.pl: a fork from vmclone.pl sample script. Originally posted [here](https://github.com/nielsengelen/vmware-perl).
  * Main changes:
    * No customize-vm/customize-guest switches (enough to pass a file/schema, if not, none is used).
    * Customize  VM directly from command line (_cpus_ and _memory_ parameters)

## Usage example

```bash
perl deploy-template.pl \
--server <VCENTER_IP> \
--username "user@vsphere.local" \
--password <password> \
--vmtemplate <VM_TEMPLATE_NAME> \
--vmhost <TARGET_ESX_HOST> \
--datastore <TARGET_DISKARRAY> \
--vmname <NEW_VM_NAME> \
--cpus 8 \
--memory 32768
```
