# Artifacts

[Azure DevTest Labs](https://docs.microsoft.com/azure/devtest-labs/devtest-lab-overview) is a cloud based service that provides a simple way for creating and managing virtual machines. Using this service you can [add an artifact](https://docs.microsoft.com/azure/devtest-labs/add-artifact-vm), which automates interactions with a virtual machine simplifying development and testing. The goal for this project is to automate the operation required to generate data for testing various cloud services. By using the Azure DevTest Labs service with a set of [custom artifacts](https://docs.microsoft.com/azure/devtest-labs/devtest-lab-artifact-author) we are able to fulfill that goal using an isolated environment that minimizes the risk since some of the artifacts being used are considered dangerous.

Below you will find details for the custom artifacts, that are part of this project, and the purpose they fulfill.

## Install provisioning package

The [install provisioning package](../src/artifacts/install-provisioning-package) artifact is used to generate a [provisioning package](https://docs.microsoft.com/windows/configuration/provisioning-packages/provisioning-how-it-works) using the [Windows Configuration Designer command line interface](https://docs.microsoft.com/windows/configuration/provisioning-packages/provisioning-command-line) and install it on the given virtual machine. Applying this artifact will perform the following operations.

* Create a new provisioning package using the defined template that will automatically join the virtual machine to Azure Active Directory and enroll it for management.
* Install the provisioning package on the virtual machine.

Once the artifact has finished applying, the virtual machine will be associated with a specific Azure Active Directory tenant and managed by Microsoft Endpoint Manager.

## New backdoor threat

The [new backdoor threat](../src/artifacts/new-backdoor-threat) artifact is used create a threat on the virtual machine using the [Squiblydoo](https://car.mitre.org/analytics/CAR-2019-04-003/) technique. This is a specific usage of regsvr32.dll to load a COM scriptlet directly from the internet and execute it in a way that bypasses the application allow listing. Applying this artifact will cause the following operations to be performed on the virtual machine.

* A new directory is created (e.g., `C:\Threats\9b34a6ocj2` where the name for the subdirectory in the `Threats` directory is randomly generated).
* A new file in the above directory will be created with content that implements [Squiblydoo](https://car.mitre.org/analytics/CAR-2019-04-003/) technique.
* The `regsvr32.exe` will be started with appropriate parameters to attempt bypassing the application allow listing.

Once this artifact has finished applying, Microsoft Defender Antivirus will have detected the attack and blocked it.

## New LSASS dump

The [new LSASS dump](../src/artifacts/new-lsass-dump) artifact is used to dump credentials found on the virtual machine using the [Credential Dumping](https://attack.mitre.org/techniques/T1003/) technique. [ProcDump](https://docs.microsoft.com/sysinternals/downloads/procdump) is used to create a dump of the Local Security Authority Server Service (LSASS) process. Applying this artifact will cause the following operations to be performed on the virtual machine.

* Installs the latest version of [Sysinternals](https://docs.microsoft.com/sysinternals/) on the virtual into the `C:\Tools\Sysinternals` directory.
* Starts the `procdump64.exe` process with the appropriate parameters to dump the `lsass.exe` process.

Once this artifact has finished applying, Microsoft Defender Antivirus will have detected the attempt to create the dump and blocked it.

## Start Defender antivirus scan

The [start Defender antivirus scan](../src/artifacts/start-defenderav-scan) artifact is used to start a full or quick scan on the virtual machine using Microsoft Defender Antivirus. Applying this artifact will start a new scan and wait until it has completed.

## Sync GitHub malware

The [sync GitHub malware](../src/artifacts/sync-github-malware) artifact is used to clone malware from various GitHub repositories to the virtual machine. Applying this artifact will cause the following operations to be performed on the virtual machine.

* A new directory is created (e.g., `C:\Threats\idrtnuwxko` where the name for the subdirectory in the `Threats` directory is randomly generated).
* Configure Microsoft Defender Antivirus to disable routinely taking action on discovered threats, which will result in the threats being discovered but no action taken to address the threat.
* Configure Microsoft Defender Antivirus to always send samples to Microsoft for further analysis as needed.
* Configure `git` to support long paths to ensure the repositories that will be cloned can successfully be cloned.
* Clone several repositories from GitHub that contain malware, ransomware, and various other threats.
* Start a Microsoft Defender Antivirus custom scan, where the target directory is the directory created through the first step.

Once this artifact has finished applying, numerous repositories that contain malware, ransomware, and various other threats will be cloned to the virtual machine. After the custom scan has completed Microsoft Defender Antivirus will have detected the threats, however, no actions will be taken due to the routinely taking action configuration being disabled.

## Sync MDM device

The [sync MDM device](../src/artifacts/sync-mdm-device) artifact is used to invoke a synchronization between the virtual machine and Microsoft Endpoint Manager. Applying this artifact will cause the following operations to be performed on the virtual machine.

* Impersonate a user from the Azure Active Directory tenant where the virtual machine is registered.
* Starts the device synchronization process which happens asynchronously.
* Checks the status of the device synchronization process and block until it has completed. If the run time exceeds fifteen minutes, then an exception will be throw.

Once this artifact has finished applying, the actions associated with the device synchronization process should have successfully been completed on the virtual machine.
