IAC Release 13.0 Transition Procedure
=====================================

This procedure outlines the steps required in order to upgrade a site to the 13.0 release. See the Release Notes for details on release content.

> Note: In the procedure below, items in all caps with <> are intended to be substituted with the appropriate value for the site.

## Table of Contents
1. [Prerequisites](#prerequisites)
1. [Procedures](#procedures)
    1. [Steps to Execute on the Old TCS](#oldtcs)
	    1. [Take a Snapshot and Save Configurations](#snapshot)
	    2. [Deploy 13.0 Release](#deploythirteen)
	    3. [Prepare Configuration Files for 13.0](#prepare)
	    4. [Create the Ansible Vault File](#createvault)
	    5. [Build a VM Template](#buildtemplate)
	    6. [Re-IP and Rename the Existing TCS](#renametcs)
	    7. [Run Playbook to Create the New TCS](#createtcs)
    2. [Steps to Execute on the New TCS](#newtcs)
	    1. [Copy and Extract 12.5 and 13.0 Install Kits](#extract)
	    2. [Fix Certificates](#fixcerts)
	    3. [Manual Artifactory Setup](#artifactory)
	    4. [Deploy 12.5 Install Kits](#deploytwelve)
	    5. [Deploy 13.0 Install Kits](#deploythirteennewtcs)
	    6. [Populate Configuration and Credentials](#credentials)
	    7. [Configure Jenkins User](#jenkins)
	    8. [Setup Configuration Synchronization Key](#sync)
    3. [Post-Deploy Steps](#postdeploy)

Prerequisites <a name=prerequisites></a>
-------------

The following are pre-requisites for the 13.0 installation and toolchain rebuild.

- The site MUST have already been updated to IAC Release 12.5 before executing these instructions.  

- Locate the IAC 12.5 larger install-kit (contains patching content). It will be needed for seeding the new toolchain host. 
  > iac-release-12.5.0-bndl-bag-delta-since-12.0.0-1700587073-installkit.tar.gz

- Ensure there is sufficient storage space in vCenter to host a second toolchain host with 2TB of storage. This will be temporary but should account for the second toolchain existing for a few days after transition is complete to account for any issues.

- The svccmx-linuxsync user will be used to copy the site-specific configuration from the local tcs host to /global01/toolchain/<site> at a remote tcs for purposes of backup. Most sites will copy to the S70 toolchain where thisuser is already setup on the S70 enclave and the private key just needs to be populated on the new TCS. Other sites willneed to import this public key.
  > Note: The public key import is part of the release notes, but the creation of the svccmx-linuxsync user and associated keypair is a prerequisite. At most sites this has already been done.

- The prerequisites discussed in the CHG TBD request must already be in place:
  - New IP address for supporting the toolchain transition
  - vCenter Content Library established

- SNAPSHOT the toolchain host before beginning

Procedures <a name=procedures></a>
----------

### Steps to Execute on the Old TCS <a name=oldtcs></a>

#### Take a Snapshot and Save Configurations<a name=snapshot></a>

  1. Snapshot the existing TCS

  2. Copy existing configuration files to new location. Do NOT skip this step. The next steps will remove the configurations and so you will lose changes if not backed up.

	cd /opt/data/site_config

	cp /opt/data/toolchain/ansible/inventory/<SITE>.ini ansible/inventory
	cp /opt/data/toolchain/ansible/inventory/group_vars/<SITE>.yml ansible/inventory/group_vars
	cp /opt/data/toolchain/ansible/inventory/host_vars/<SITE_HOSTPREFIX>*.yml ansible/inventory/host_vars
	cp /opt/data/toolchain/patching_config/linux/*<SITE>*.yml patching_config/linux
	cp /opt/data/toolchain/patching_config/windows/*<SITE>*.yml patching_config/windows
	
#### Deploy 13.0 Release<a name=deploythirteen></a>

Some new functionality from the 13.0 release is necessary on the OLD TCS in order to prep for the RHEL 8/NEW TCS Build. Extract and install 13.0.

  1. Remove the existing configurations from the filesystem. This is to avoid picking up old information after the transition to the new configuration structure.
			
	sudo rm -rf /opt/data/toolchain/ansible
	sudo rm -rf /opt/data/toolchain/patching_config

  2. Deploy the IAC 13.0 baseline installkit. 
	   > Note: If prompted for a group when running the deploy, use "jenkins"

	sudo cp <GLOBAL01 LOCATION>/iac-release-13.0.0-bundle-1705556288-installkit.tar.gz /opt/data/toolchain/staging
	sudo cp <GLOBAL01 LOCATION>/iac-release-13.0.0-code-only-1705555953-installkit.tar.gz /opt/data/toolchain/staging
 
	cd /opt/data/toolchain/staging
 
	sudo tar xzf iac-release-13.0.0-bundle-1705556288-installkit.tar.gz
	sudo tar xzf iac-release-13.0.0-code-only-1705555953-installkit.tar.gz
 
	cd iac-release-13.0.0-bundle-1705556288-installkit
	sudo ./deploy-artifacts.sh -e
 
	cd ../iac-release-13.0.0-code-only-1705555953-installkit
	sudo ./deploy-artifacts.sh -e
	
#### Prepare Configuration Files for 13.0<a name=prepare></a>

Update configuration files to support the build of the new TCS host and the 13.0 Release. Note that these steps assume that the existing TCS will be re-IPed to tcs002. 

1. INVENTORY - Add the temporary "tcs002" to the toolchain group.
	Edit  /opt/data/site_config/ansible/inventory/<SITE>.ini, and add the new host following the example below.
	
	13.0 Inventory update:
		
	   [toolchain]
	   cmfsvs5gctcs001 # New redhat 8
	   cmfsvs5gctcs002 # Old redhat 7, this is temporary

  2. HOST VARS -
    /opt/data/site_config/ansible/inventory/host_vars

		1. TCS Host
			- UPDATE host_vars file for tcs001 host 
				- Confirm vm_static_ip is the correct IP (should be the existing .158)
				- Remove ansible_user if defined
			
			The resulting file should look something like the following:

			13.0 Host Vars update - template:
			
			   vm_static_ip: 10.2.25.158
			   ansible_ssh_host: "{{ vm_static_ip }}"

		2. CREATE a host vars file for the tcs002 old/tcs host and add a line to point to the correct artifactory.

				cd /opt/data/site_config/ansible/inventory/host_vars
				cp <OLDTCS_001>.yml <NEWTCS_002>.yml
				cat "artifactory_url: \"https://{{ infra_subnet }}.158:8081/artifactory\"" >> <NEWTCS_002>.yml

		3. Other Hosts

			- With the new way of providing credentials, the ansible_user: root variable in the Linux host vars files will cause issues for command-line hardening/agent installation.
			- Update all linux host_vars files to remove ansible_user.

  3. GROUP VARS

	  /opt/data/site_config/ansible/inventory/group_vars/<SITE>.yml

		1. UPDATE existing Group Vars content 

			CONFIRM that artifactory_url and artifactory_resolve_repo are correct
	
			   artifactory_url: "https://{{ infra_subnet }}.158:8081/artifactory"
			   artifactory_resolve_repo: iactc-virt
	
			ADD a new artifactory variable in the same section
	
			   artifactory_resolve_url: "{{ artifactory_url }}/{{ artifactory_resolve_repo }}"

			REMOVE any setting of vcenter_username, vcenter_password, join_domain_ad_username, join_domain_ad_password

		2. ADD NEW Group Vars content for release 13.0 as noted below

			It is suggested that these settings be placed at the end of the file and noted with IAC 13.0 updates.

			Copy and paste the below section, and then change all items with <> to match your environment. Note: if using vi, use ":set paste" command to prevent it from indenting for all the comments when pasting the content.

			13.0 group_vars update:
	
			   # IAC 13.0 Updates
			   enclave: <ENCLAVE> # ex: ts
 
			   # Controls location of site inventory.
		       site_config_inventory_src: "/opt/data/site_config/ansible/inventory/{{ufc}}_{{enclave}}.ini"
 
			   # Controls the syncing of configuration to "mompod" for backup
			   upstream_tcs: <S70_TCSIP> # host to sync to, S70 TCS for all sites except T25 and R46 which should use the local TCS
			   upstream_service_account: svccmx-linuxsync # account to use for syncing, already exists
 
			   # Used for vm template builds
			   vcenter_template_folder: "{{ vm_folder }}/templates" # Parent folder for templates
			   vcenter_content_library_name: <CONTENT_LIBRARY> # Example: UBE-452679-Infra-ContentLibrary
			   vcenter_template_datastore: <ANY DATASTORE> # Note must NOT be a DRS, so something like "UBE-452679-IaC-VM-4"
 
			   # Jenkins and Artifactory credentials to be loaded into Jenkins
			   jenkins_credentials:
				 - id:          c82f9698-8731-44c9-b3df-0ea02998fa59
				   description: "Artifactory Credentials"
				   username:    "{{ vault_artifactory_admin_username }}"
				   password:    "{{ vault_artifactory_admin_password }}"
				 - id:          linux_srv_acct
				   description: "Linux Service Account"
				   username:    "{{ vault_linux_admin_username }}"
				   password:    "{{ vault_linux_admin_password }}"
				 - id:          windows_admin
				   description: "Windows Domain Account"
				   username:    "{{ vault_windows_admin_username }}"
				   password:    "{{ vault_windows_admin_password }}"
			   # Enterprise admin is same as windows domain
				 - id:          enterprise_admin
				   description: "Forest Domain Account"
				   username:    "{{ vault_windows_admin_username }}"
				   password:    "{{ vault_windows_admin_password }}"
				 - id:          vcenter-imperious
				   description: "vCenter Credentials"
				   username:    "{{ vault_vcenter_username }}"
				   password:    "{{ vault_vcenter_password }}"
			   artifactory_ldap_settings:
			     - name: adc
				   ldap_url: "ldap://{{ad_servers[0]}}:389/dc={{ ad_domain.replace('.',',dc=') }}"
				   user_dn_pattern: ""
				   search_filter: sAMAccountName={0}
				   search_base: ""
				   manager_dn: "{{ vault_ad_join_domain_username }}@{{ ad_domain }}"
				   manager_password: "{{ vault_ad_join_domain_password }}"
		
#### Create the Ansible Vault File<a name=createvault></a>

With 13.0 the credentials for command line ansible use will be stored in a central vault file instead of a personal vault file. This needs to be setup on the OLD TCS host in order to support the build of the NEW TCS.

1. Manually install python3 (will be available on new RHEL 8 TCS, but needed here to support the transition).

	   sudo yum install python3
2. Run the new "ansible-vault-create" script to create the vault file.  The g parameter is to set the proper group on the vault and credential files.  This should be set to the "sudo-admin" group and that name varies by site. 

	   cd /opt/data/toolchain/scripts
	   sudo ./ansible-vault-create -g <UFC>-sudo-admin
3. Follow instructions to populate the vault file with credentials. 

	| Credential                                                                | How to set                                                                        |
	|---------------------------------------------------------|---------------------------------------------------------------|
	| vault_linux_root_password                                    | Existing value                                                                    |
	| vault_linux_root_pwhash                                       | Run this command, and when prompted, give it the normal root password value <br /> python -c 'import crypt,getpass;pw=getpass.getpass();print(crypt.crypt(pw) if (pw==getpass.getpass("Confirm: ")) else exit())' |
	| vault_linux_grub_pwhash                                      | Run this command, and when prompted, give it the normal root password value <br /> grub2-mkpasswd-pbkdf2 |
	| vault_vcenter_username/password                      | svccmX-tcs                                                                        |
	| vault_ad_join_domain_username/password	        | svccmX-vdomjoin                                                            |
	| vault_jenkins_admin_username/password           | admin <br /> Existing value for pw                               |
	| vault_artifactory_admin_username/password     | admin <br /> Existing value for pw                               |
	| vault_satellite_admin_username/password          | admin <br /> Note: This credential isn't actually used yet |
	| vault_linux_admin_username/password               | svccmX-tcs                                                                       |
	| vault_windows_admin_username/password        | svccmX-winadm                                                              |
	| vault_windows_administrator_password              | Existing value                                                                   |

#### Build a VM Template<a name=buildtemplate></a>

1. Confirm that the content library exists in vcenter as per release notes and matches name in the site group_vars

2. Confirm that the "templates" folder exists in vcenter that matches the vcenter_template_folder in the site group_vars

3. Manually install packer (will be available on new RHEL 8 TCS, but needed here to support the transition).

	Respond "yes" on the unzip prompt

	   mkdir /tmp/downloads 
	   curl https://$HOSTNAME:8081/artifactory/iactc-thirdparty/com/hashicorp/packer/1.8.2/packer-1.8.2-linux_amd64.zip -o /tmp/downloads/packer-1.8.2-linux_amd64.zip
	   cd /usr/bin
       sudo unzip /tmp/downloads/packer-1.8.2-linux_amd64.zip
	   rm -rf /tmp/downloads
4. Run the template creation playbook. This will take 20-30 minutes

	   source /opt/data/toolchain/scripts/manual-exec-setup.sh
 
	   cd /opt/data/toolchain/ansible
 
	   ansible-playbook playbooks/template-build.yml \
	   -e@/opt/data/toolchain/credentials/ansible-vault.yml  \
	   -e@/opt/data/site_config/ansible/inventory/group_vars/<SITE>.yml
5. When complete, browse the content library and confirm existence of new template.

#### Re-IP and Rename the Existing TCS<a name=renametcs></a>

The old TCS must be re-iped so the new one about to be built can have the original name and IP.

1. Confirm current IP, hostname and network interface. 

	   ip a
	   hostnamectl status
2. Update the IP. The interface you will need to change is the one with the current ip of the host. Probably either ens160 or ens192. Change the IPADDR setting to be the new IP.

	   sudo vi /etc/sysconfig/network-scripts/ifcfg-<INTERFACE>
3. Change the hostname. For the below command set the new servername to be the 002 hostname with the same fqdn as shown from the status command above.

	   sudo hostnamectl set-hostname <TCS002>
4. Reboot the host

5. Log back in using the NEW IP. Confirm the IP and hostname are updated using the commands from the first step above. Do an nslookup of the new hostname to confirm it is in DNS.

6. From vCenter, rename the old host to the new hostname.

#### Run Playbook to Create the New TCS<a name=createtcs></a>

Run the toolchain playbook. This will take about an hour.

The OLDTCSHOST_IP is the IP we just switched to ".159". This is necessary to ensure the build process doesn't look for the new artifactory which doesn't yet exist.

	cd /opt/data/toolchain/ansible
	source /opt/data/toolchain/scripts/manual-exec-setup.sh
 
	ansible-playbook -i /opt/data/site_config/ansible/inventory/<SITE>.ini -i /opt/data/toolchain/ansible/inventory/default.ini -e@/opt/data/toolchain/credentials/ansible-vault.yml playbooks/toolchain.yml -e artifactory_url="https://<OLDTCSHOST_IP>:8081/artifactory" --limit <NEWTCSHOST_NAME>

### Steps to Execute on the New TCS <a name=newtcs></a>

#### Copy and Extract 12.5 and 13.0 Install Kits<a name=extract></a>

The new TCS will need the 12.5 bundle/bag (large) installkit, plus the two 13.0 installkits (bundle/cots/foss, code). The easiest thing to do will be to pull from your old TCS, since the 12.5/large installkit is not currently available on UBE storage.

Completing these steps may take an hour or more given the size of the files.

	sudo mkdir /opt/data/toolchain/staging
	cd /opt/data/toolchain/staging
 
	sudo scp $USER@<TCS002>:/opt/data/toolchain/staging/iac-release-12.5.0-bndl-bag-delta-since-12.0.0-1700587073-installkit.tar.gz .
	sudo scp $USER@<TCS002>:/opt/data/toolchain/staging/iac-release-13.0.0-bundle-1705556288-installkit.tar.gz .
	sudo scp $USER@<TCS002>:/opt/data/toolchain/staging/iac-release-13.0.0-code-only-1705555953-installkit .
 
	sudo tar xzf iac-release-12.5.0-bndl-bag-delta-since-12.0.0-1700587073-installkit.tar.gz
	sudo tar xzf iac-release-13.0.0-bundle-1705556288-installkit.tar.gz
	sudo tar xzf iac-release-13.0.0-code-only-1705555953-installkit.tar.gz

#### Fix Certificates<a name=fixcerts></a>

The TCS needs proper certs, not self-signed ones, there are scripts in the 13.0 install kit to fix this.  

1. Lookup the existing toolchain keystore password from the password spreadsheet

2. Follow the steps below.

	Use the local site pki server select "Web Server" as type.
When prompted for password at step 3, use the password retrieved from the password spreadsheet
cd /opt/data/toolchain/staging/iac-release-13.0.0-code-only-1705555953-installkit
 
	   sudo ./new-cert-and-keystores.sh 1
 
	< follow instructions >
 
	   sudo ./new-cert-and-keystores.sh 2
	   sudo ./new-cert-and-keystores.sh 3

#### Manual Artifactory Setup<a name=artifactory></a>

A few manual steps are required to fully configure artifactory. After completion, be sure to log out because I've seen an error that made me thing only one admin and a time can be logged in and future steps may fail.

The service account to use is svccmX-linux where X varies by site

1. Set up svccmX-linux account in NEW Artifactory.  

	- Log in to the Artifactory GUI with the linux service account to establish its Artifactory account (created automatically on login, retrieved from AD), then log out.
	- Log in to the Artifactory GUI with the default admin account (admin) and update account to have admin privileges.  
	- From the admin menu on the left (the person icon at the bottom), under 'Security', click 'Users'.
	- Click on the account in the 'Name' column.
	- Check the box for 'Admin Privileges', then click 'Save'.
	- Enter an email address (can be your own) the page won't let you save until this is added.
2. Disable Artifactory backup  

	- As admin, manually disable the "backup-daily" backup job:
		- From the admin menu on the left (the person icon at the bottom), under 'Services', click 'Backups'.
Click 'backup-daily' in the 'Key' column.
		- Un-check the 'Enabled' box at the top, then click 'Save'.

#### Deploy 12.5 Install Kit<a name=deploytwelve></a>

Install 12.5 Install Kit to populate the patching content and do maven initial setup on the NEW TCS host.

1. Copy 13.0 scripts from previously extracted 13.0 installkit over to support running on a RHEL 8 host.

	   cd /opt/data/toolchain/staging/iac-release-13.0.0-code-only-1705555953-installkit
 
	   sudo cp deploy-artifacts.sh tcs-cmd-line-utils.sh yum_install_maven_rhel8.sh ../iac-release-12.5.0-bndl-bag-delta-since-12.0.0-1700587073-installkit
2. Run the installation. This will take up to two hours and will install maven and the 12.5 patching configs. It will complete with validation errors, but this is ok.

	When prompted, use the site specific "svccmX-linux" account (where X varies by site) and password NOT admin.

	   cd /opt/data/toolchain/staging/iac-release-12.5.0-bndl-bag-delta-since-12.0.0-1700587073-installkit
	   sudo ./deploy-artifacts.sh -e
3. Once complete, re-source your .bashrc to confirm maven is now available in your path. If it is not, the next steps will fail.

	   source ~/.bashrc
	   which xmvn # should find /opt/rh/maven30/root/usr/bin/xmvn
4. Log into artifactory and navigate to the iactc-delivered repository. Confirm that 12.5.0 content is found under com/rtx/iac/patching

#### Deploy 13.0 Install Kits<a name=deploythirteennewtcs></a>

Deploy both the 3rd Party (bundle) and code.

When prompted, use the site specific service account as noted above and NOT admin.

	cd /opt/data/toolchain/staging/iac-release-13.0.0-bundle-1705556288-installkit
	sudo ./deploy-artifacts.sh -e
 
	cd /opt/data/toolchain/staging/iac-release-13.0.0-code-only-1705555953-installkit
	sudo ./deploy-artifacts.sh -e

#### Populate Configuration and Credentials<a name=credentials></a>

1. Either repeat the credential setup steps from prior section, or copy the vault file from the old TCS.  You will be prompted for the root password.

	   sudo rsync -a root@<TCS002>:/opt/data/toolchain/credentials /opt/data/toolchain/
2. Copy configuration data. You will be prompted for your personal password. 

	   sudo rsync -a $USER@<TCS002>:/opt/data/site_config /opt/data/

#### Configure Jenkins User<a name=jenkins></a>

The jenkins user needs to be able to SSH as the linux service account (svccmX-linux, where X varies by site) in order to execute linux patching.  These steps correctly set up the jenkins user so that it can do this.

	sudo su - jenkins
	ssh-copy-id <LINUX_SVC_ACCOUNT>@localhost
	ssh '<LINUX_SVC_ACCOUNT>@localhost'
	exit
	exit

#### Setup Configuration Synchronization Key<a name=sync></a>

Copy the synchronization key which will be used to replicate the site_config to the /global01/toolchain area on S70 (most sites). On T25 and R46 this will be copied to the local toolchain host.

For mosts hosts using S70, the svccmx-linuxsync user already exists on S70. For R46 and T25 create a local account on the toolchain host to simulate this.

R46 and T25 only: Create a local svccmx-linuxsync account and locally setup the key

R46 and T25 only instructions

	sudo useradd svccmx-linuxsync
	sudo su - svccmx-linuxsync
	ssh-keygen
	cp .ssh/id_rsa .ssh/authorized_keys
	exit
	sudo copy ~svccmx-linuxsync/.ssh/id_rsa /root/.ssh/svccmx-linuxsync


NOT R46/T25 - All other site instructions: Pull the pre-existing key from S70 TCS into the local TCS

	sudo scp svccmx-linuxsync@<S70_TCS>:~/.ssh/id_rsa /root/.ssh/svccmx-linuxsync
ALL SITES: Confirm that the key is working by manually running the cronjob

	sudo su -
	crontab -l
	# Copy and paste the cron command line to run manually, will look something like this
 
	ssh svccmx-linuxsync@<REMOTE_TCS> -i /root/.ssh/svccmx-linuxsync "mkdir -p /global01/toolchain/<SITE>" ; rsync -avzhP -e "ssh -i /root/.ssh/svccmx-linuxsync" /opt/data/site_config/ svccmx-linuxsync@162.36.191.140:/global01/toolchain/<SITE>/
Log into the destination host and confirm your configuration was copied. You should see your sandbox folder

	ssh $USER@<REMOTE_TCS>
	ls -l /global01/toolchain

### Post-Deploy Steps <a name=postdeploy></a>

To ensure credentials and inventory files are correct it is recommended to test functionality after completing the release. Note that no changes are expected based on these tests since the site should have been completely patched and hardened withthe 12.5 baseline and no updates in this area are present in the 13.0 release.

Run the following Jenkins workflow and confirm no errors. Follow instructions in the Operations Manual.
Note: For the patching workflows, no new patches will be applied because the system should have been fully patched with 12.5 and the patching content is not updated with this delivery.
  - Configure WSUS
  - Patch Windows (pick one host or a small subset of hosts)
  - Build Yum Server workflow (pick the 12.5 content)
  - Patch Linux (pick one host or a small subset of hosts)
  - Run hardening against linuxservers

After the above have been confirmed to be operating, cleanup the toolchain snapshot and shutdown the old toolchain.
