#!/usr/bin/perl -w
# Deploy a VM from template with some standard parameters
# Modify the default config value to the correct parameters
#
# Feel free to use and/or edit
#
# Initial version: 2013 - Niels Engelen

# Vmhost
# perl deploy-template.pl \
#--server <VCENTER_IP> \
#--username "user@vsphere.local" \
#--password <password> \
#--vmtemplate <VM_TEMPLATE_NAME> \
#--vmhost <TARGET_ESX_HOST> \
#--datastore <TARGET_DISKARRAY> \
#--vmname <NEW_VM_NAME> \
#--cpus 8 \
#--memory 32768


use strict;
use warnings;
use POSIX qw(ceil floor);
use VMware::VIRuntime;
use VMware::VILib;
use VMware::VICommon;

use AppUtil::VMUtil;
use AppUtil::HostUtil;
use AppUtil::XMLInputUtil;

# Ignore SSL warnings or invalid server warning
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

# Default VM config
my $cpus = 1;
my $memory = 1024;

# Changeable options
my %opts = (
        vmhost => {
                type => "=s",
                help => "ESXi Host in cluster to deploy VM to",
                required => 1,
                default => "esxi-host",
        },
        vmtemplate => {
                type => "=s",
                help => "Name of VM Template (source VM)",
                required => 1,
                default => "vmMachineTemplate",
        },
        vmname => {
                type => "=s",
                help => "Name to set for the new VM",
                required => 1,
        },
        datastore => {
                type => "=s",
                help => "Name of datastore in vCenter",
                required => 0,
        },
        folder => {
                type => "=s",
                help => "Folder where to deploy the new VM. If not defined, the value is the same folder as the template",
                required => 0,
        },
        memory => {
                type => "=s",
                help => "Amount of Memory (RAM) on the new VM",
                required => 0,
                default => $memory,
        },
        cpus => {
                type => "=s",
                help => "Number of CPUs on the new VM",
                required => 0,
                default => $cpus,
        },
        xml_file => {
                type => "=s",
                help => "The name of the configuration specification file",
                required => 0,
                default => "sampledata/vmclone.xml",
        },
        xml_schema => {
                type => "=s",
                help => "The name of the schema file",
                required => 0,
                default => "sampledata/vmclone.xsd",
        },
);

Opts::add_options(%opts);
Opts::parse();
Opts::validate(\&validate);

my $vmname = Opts::get_option('vmname');

sub deploy_template() {
        my ($vmtemplate, $datastore, $resourcepool, $cpus, $folder, $comp_res_view, $vm_views, $vmhost);

        if (Opts::get_option('datastore')) { $datastore = Opts::get_option('datastore'); }
        if (Opts::get_option('vmtemplate')) { $vmtemplate = Opts::get_option('vmtemplate'); }
        if (Opts::get_option('vmhost')) { $vmhost = Opts::get_option('vmhost'); }
        if (Opts::get_option('cpus')) { $cpus = Opts::get_option('cpus'); }

        $vm_views = Vim::find_entity_views( view_type => 'VirtualMachine', filter => { 'name' => $vmtemplate } );

        if (@$vm_views) {
                foreach (@$vm_views) {
                        my %relocate_params;
                        my %datastore_info;
                        my $host_view;
                        if ($vmhost) {
                                $host_view = Vim::find_entity_view( view_type => 'HostSystem', filter => { 'name' => $vmhost } );
                                unless ($host_view) {
                                        Util::disconnect();
                                        die "ESXi Host '$vmhost' not found\n";
                                }
                        }

                        $comp_res_view = Vim::get_view( mo_ref => $host_view->parent );

                        %datastore_info = get_datastore( host_view => $host_view, datastore => $datastore );

                        if (not $resourcepool) { $resourcepool = $comp_res_view->resourcePool;  }

                        %relocate_params = ( datastore => $datastore_info{mor}, pool => $resourcepool );

                        my $relocate_spec = get_relocate_spec(%relocate_params);
                        my $config_spec = get_config_spec();
                        my $customization_spec = VMUtils::get_customization_spec(Opts::get_option('xml_file'));;

                        my $clone_spec = VirtualMachineCloneSpec->new( powerOn => 1, template => 0, location => $relocate_spec, config => $config_spec, customization => $customization_spec );

                        Util::trace (0, "Deploying virtual machine from template " . $vmtemplate . "...\n");

                        if (Opts::get_option('folder')) {
                                my $folder_name = Opts::get_option('folder');
                                $folder = Vim::find_entity_view( view_type => 'Folder', filter => { 'name' => $folder_name } );
                        } else {
                                $folder = $_->parent;
                        }

                        eval {
                                $_->CloneVM(  folder => $folder,
                                              name => $vmname,
                                              spec => $clone_spec );
                                Util::trace (0, $vmname . " (template " . $vmtemplate . ") successfully deployed.\n");
                        };

                        if ($@) {
                           if (ref($@) eq 'SoapFault') {
                              if (ref($@->detail) eq 'FileFault') {
                                 Util::trace(0, "\nFailed to access the virtual "
                                                ." machine files\n");
                              }
                              elsif (ref($@->detail) eq 'InvalidState') {
                                 Util::trace(0,"The operation is not allowed "
                                               ."in the current state.\n");
                              }
                              elsif (ref($@->detail) eq 'NotSupported') {
                                 Util::trace(0," Operation is not supported by the "
                                               ."current agent \n");
                              }
                              elsif (ref($@->detail) eq 'VmConfigFault') {
                                 Util::trace(0,
                                 "Virtual machine is not compatible with the destination host.\n");
                              }
                              elsif (ref($@->detail) eq 'InvalidPowerState') {
                                 Util::trace(0,
                                 "The attempted operation cannot be performed "
                                 ."in the current state.\n");
                              }
                              elsif (ref($@->detail) eq 'DuplicateName') {
                                 Util::trace(0,
                                 "The name '$vmname' already exists\n");
                              }
                              elsif (ref($@->detail) eq 'NoDisksToCustomize') {
                                 Util::trace(0, "\nThe virtual machine has no virtual disks that"
                                              . " are suitable for customization or no guest"
                                              . " is present on given virtual machine" . "\n");
                              }
                              elsif (ref($@->detail) eq 'HostNotConnected') {
                                 Util::trace(0, "\nUnable to communicate with the remote host, "
                                                ."since it is disconnected" . "\n");
                              }
                              elsif (ref($@->detail) eq 'UncustomizableGuest') {
                                 Util::trace(0, "\nCustomization is not supported "
                                                ."for the guest operating system" . "\n");
                              }
                              else {
                                 Util::trace (0, "Fault" . $@ . ""   );
                              }
                           }
                           else {
                              print ref($@);
                              Util::trace (0, "Fault" . $@ . ""   );
                           }
                        }
                      }
        } else {
                Util::trace (0, "Virtual machine template not found: " . $vmtemplate . "\n");
        }
}


sub get_config_spec() {
        my $memory = Opts::get_option('memory');
        my $cpus = Opts::get_option('cpus');
        my $config_spec = VirtualMachineConfigSpec->new( name => $vmname, memoryMB => $memory, numCPUs => $cpus );
        return $config_spec;
}

sub get_relocate_spec() {
        my %args = @_;
        my $datastore = $args{datastore};
        my $resourcePool = $args{pool};
        my $relocate_spec = VirtualMachineRelocateSpec->new( datastore => $datastore, pool => $resourcePool );
        return $relocate_spec;
}

sub get_datastore {
        my %args = @_;
        my $host_view = $args{host_view};
        my $config_datastore = $args{datastore};
        my $name;
        my $mor;

        my $ds_mor_array = $host_view->datastore;
        my $datastores = Vim::get_views( mo_ref_array => $ds_mor_array );

        my $found_datastore = 0;

        # User specified datatstore name
        if (defined($config_datastore)) {
                foreach (@$datastores) {
                        $name = $_->summary->name;
                        if ($name eq $config_datastore) { # Is the datastore available to the specific host?
                                $found_datastore = 1;
                                $mor = $_->{mo_ref};
                                last;
                        }
                }
        }
        # No datatstore name specified
        else {
                my $disksize = 0;
                foreach (@$datastores) {
                        my $ds_disksize = ($_->summary->freeSpace);
                        if($ds_disksize > $disksize && $_->summary->accessible) {
                                $found_datastore = 1;
                                $name = $_->summary->name;
                                $mor = $_->{mo_ref};
                                $disksize = $ds_disksize;
                        }
                }
        }

        if (!$found_datastore) {
                my $host_name = $host_view->name;
                my $datastore = "<any accessible datastore>";
                if (Opts::option_is_set('datastore')) {
                        $datastore = Opts::get_option('datastore');
                }
                die "Datastore '$datastore' is not available to host $host_name\n";
        }

        return ( name => $name, mor => $mor );
}

sub validate {
  my $valid= 1;

  $valid = XMLValidation::validate_format(Opts::get_option('xml_file'));
  if ($valid == 1) {
  $valid = XMLValidation::validate_schema(Opts::get_option('xml_file'),
                                       Opts::get_option('xml_schema'));
  }
  return $valid;
}


Util::connect();

deploy_template();

Util::disconnect();
