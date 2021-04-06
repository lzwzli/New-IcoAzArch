#=============================================================================================================================
# This script will create VMs with the latest ICONICS Azure Marketplace offers for the chosen version.
# All resources created by this script will be placed in the resource group of your choice.
# A new resource group will be created if it doesn't exist.
# VMs can be created in any region that is supported by your subscription.
#
# Author: Zhi Wei Li
# Dev Version: 7.0
# Publish date: Apr 6th, 2021
# 
# Release Version: 1.7
# Release date: Apr 6th, 2021
#
#=============================================================================================================================

#Parameters
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [String]$SubscriptionName,
    [Parameter(Mandatory=$false)]
    [String]$ResourceGroupName,
    [Parameter(Mandatory=$false)]
    [String]$Location,
    [Parameter(Mandatory=$false)]
    [String]$VMCount,
    [Parameter(Mandatory=$false)]
    [String]$VMSize,
    [Parameter(Mandatory=$false)]
    [String]$UseSSD,
    [Parameter(Mandatory=$false)]
    [String]$VMPrefix,
    [Parameter(Mandatory=$false)]
    [String]$ICONICSversion,
    [Parameter(Mandatory=$false)]
    [String]$Username,
    [Parameter(Mandatory=$false)]
    [String]$Password,
    [Parameter(Mandatory=$false)]
    [String]$AllowHTTP,
    [Parameter(Mandatory=$false)]
    [String]$AllowFWX,
    [Parameter(Mandatory=$false)]
    [String]$Confirm,
    [Parameter(Mandatory=$false)]
    [String]$AsJob
)

#Wait job function
function WaitJob {
    param ([Parameter(Mandatory=$false)][string]$Command)
    IF(!$Command){
        #Get job state
        $jobState=Get-Job | Select-Object -Property State
    }
    ELSE{
        #Get job state
        $jobState=Get-Job -Command ('*'+$Command+'*') | Select-Object -Property State
    }

    #Initialize animation
    $cursorTop = [Console]::CursorTop
    [Console]::CursorVisible=$false
    $counter=0
    $frames = '|','/','-','\'

    #While jobs are still running, show animation
    while($jobState -match 'Running'){
        $frame=$frames[$counter % $frames.length]

        write-host $frame -NoNewline
        [Console]::SetCursorPosition(0,$cursorTop)

        $counter+=1
        Start-Sleep -milliseconds 125

        IF(!$Command){
            #Get job state
            $jobState=Get-Job | Select-Object -Property State
        }
        ELSE{
            #Get job state
            $jobState=Get-Job -Command ('*'+$Command+'*') | Select-Object -Property State
        }
    }

    #Reset console
    [Console]::SetCursorPosition(0,$cursorTop)
    [Console]::CursorVisible=$true    
}

function PrintStatus {
    [CmdletBinding()]
    param ([string]$ToPrint)
    write-host ('='*200)	
    write-host $ToPrint
    write-host ('='*200)
}

function PrintError {
    param ([string] $ErrorMessage, [bool]$IsError=$true)
    IF ($IsError -eq $true) {
        Write-Host ' !! ERROR:'$ErrorMessage' !! ' -ForegroundColor White -BackgroundColor Red -NoNewline
        write-host ' '
    }
    ELSE {
        Write-Host ' !!'$ErrorMessage' !! ' -ForegroundColor White -BackgroundColor Red -NoNewline
        write-host ' '
    }
}

function PrintYesNoOption {
    write-host ' [Y] ' -ForegroundColor white -BackgroundColor Black -NoNewline
    Write-Host ' ' -NoNewline
    write-host ' [N] ' -ForegroundColor white -BackgroundColor Black -NoNewline
    Write-Host ' '
}

function PrintYesNoError {
    PrintError 'Y for Yes, N for No'
}

function PrintYESNO {
    param ([string]$Allow)
    IF ($Allow -eq 'Y'){
        $Allow='YES'
    }
    ELSE {
        $Allow='NO'
    }
    Return $Allow
}

function PrintConfirmationEntry {
    param ([string]$MsgPrefix, [string]$Content)

    write-host $MsgPrefix -NoNewline
    write-host ' ' -NoNewline
    write-host $Content -ForegroundColor Yellow  -NoNewline
    write-host ' '
}

function ChangeSubscription {
    $changeSubscription=''
    while (-NOT($changeSubscription -eq 'Y' -OR $changeSubscription -eq 'N')){
        IF ($changeSubscription -and ($changeSubscription -ne 'Y' -and $changeSubscription -ne 'N')){
            PrintYesNoError
        }
        
        Write-Host 'Do you want to change your subscription ? ' -foregroundcolor green -NoNewline
        PrintYesNoOption
        [string]$changeSubscription = Read-Host 'Change Subscription'
    }
    return $changeSubscription
}

function GetResourceGroupName {
    $resourceGroupName=''
    while ($resourceGroupName -eq '' -or $resourceGroupName -match ' ' -or $resourceGroupName -match '(?=.*[*#&+:<>?])'){
        write-host 'Enter a resource group name. If a resource group with the entered name doesn''t exist, a new one will be created. ' -foregroundcolor green -NoNewline
        write-host 'No spaces. Alphanumeric characters only.' -ForegroundColor Red -NoNewline
        write-host ' '
        [string]$resourceGroupName=Read-Host 'Resource group name'

        #Has spaces
        IF ($resourceGroupName -match ' '){
            PrintError 'Resource group names cannot have spaces.'
        }
        #Has non-alphanumeric characters
        ELSEIF ($resourceGroupName -match '(?=.*[*#&+:<>?])'){
            PrintError 'Resource group names can only contain alphanumeric characters.'
        }
        ELSE{
            #Repeat
        }
    }
    return $resourceGroupName   
}

function ChangeResourceGroupName {
    $setResourceGroupName=''
    while (-NOT($setResourceGroupName -eq 'Y' -OR $setResourceGroupName -eq 'N')){
        IF($setResourceGroupName -and($setResourceGroupName -ne 'Y' -and $setResourceGroupName -ne 'N')){
            PrintYesNoError
        }

        write-host 'Resource group already exist. VMs and related resources will be created in the existing group.' -ForegroundColor Yellow
        write-host 'Do you want to use a different resource group name ? ' -ForegroundColor Green -NoNewline
        PrintYesNoOption

        $setResourceGroupName = Read-Host 'Change resource group name?'
    }
    return $setResourceGroupName
}

function GetAzureRegion {
    $location=''            
    #Throw error if $location has spaces or is not valid
    while ($location -eq '' -or $location -match ' ' -OR -NOT($azlocations -like '*='+$location+'}*')){
        write-host 'Enter Azure region ' -foregroundcolor green -NoNewline
        write-host 'in lowercase and without spaces.' -ForegroundColor Red -NoNewline
        write-host ' '
        [string]$location=Read-Host 'Azure region'
        $location=$location.ToLower()

        #Tell user we're validating region
        Write-Host '~~ Validating region ~~' -ForegroundColor Yellow -NoNewline
        Write-Host ' '

        #Get Azure region list
        $azlocations=Get-AzLocation | Select-Object -Property Location

        #Error if has spaces
        IF($location -match ' '){
            PrintError 'Azure region cannot have spaces.'
        } 
        #Error for invalid region
        ELSEIF (-NOT($azlocations -like '*='+$location+'}*')){
            PrintError 'Azure region is not valid for your subscription.'
        } 
        ELSE{
            #Continue
        }
    }
    #Tell user region validated
    write-host 'Region validated.'
    return $location
}

function GetVMsize {
    $vmSize=''
    #Check for Standard prefix and if the sizes are valid
    while ($vmSize -eq '' -or $vmSize -match 'Standard' -OR -NOT($azVMsizes -like '*=Standard_'+$vmSize+'}*')){
        write-host 'Enter VM size name ' -foregroundcolor green -NoNewline
        write-host 'without ''Standard'' prefix.' -ForegroundColor red -NoNewline
        write-host ' '
        [string]$vmSize=Read-Host 'VM size'

        #Tell user we're validating sizes
        write-host '~~ Validating VM size ~~' -foregroundcolor Yellow -NoNewline
        write-host ' '

        #Get Azure VM size list
        $azVMsizes=Get-AzVMSize -location $location | Select-Object -Property Name

        IF($vmSize -match 'Standard'){
            PrintError 'Enter VM size without ''Standard'' prefix.'
        }
        ELSEIF(-NOT($azVMsizes -like '*=Standard_'+$vmSize+'}*')){
            PrintError 'VM size invalid for the selected region/subscription.'
        }
    }

    #Tell user VM size validated
    Write-Host 'VM size validated.'
    return $vmSize
}

function GetSSDOption {
    $SSD=''
    while (-NOT($SSD -eq 'Y' -OR $SSD -eq 'N')){
        IF($SSD -and($SSD -ne 'Y' -and $SSD -ne 'N')){
            PrintYesNoError
        }

        write-host 'Do you want to use SSD for the OS disk ? ' -ForegroundColor Green -NoNewline
        PrintYesNoOption

        $SSD = Read-Host 'Use SSD'
    }
    return $SSD
}

function GetVMName {
    $vmName=''
    #Check $vmName for length, spaces and non-alphanumeric characters
    while ($vmName -eq '' -or $vmName.length -gt 12 -or $vmName -match ' ' -or $vmName -match '(?=.*[\/"''\[\]:\|<>+=;,\?\*@&_])'){
        Write-Host 'Enter VM prefix name. ' -ForegroundColor Green -NoNewline
        write-host 'Less than 12 characters. No spaces. Alphanumeric characters only.' -ForegroundColor Red -NoNewline
        write-host ' '
        [string]$vmName=Read-Host 'VM prefix'

        #Has spaces
        IF ($vmName -match ' '){
            PrintError 'VM prefix name cannot have spaces.'
        }
        #Longer than 12
        ELSEIF ($vmName.length -gt 12){
            PrintError 'VM prefix name must be less than 12 characters.'
        }
        #Has non-alphanumeric characters
        ELSEIF ($vmName -match '(?=.*[\/"''\[\]:\|<>+=;,\?\*@&_])'){
            PrintError 'VM prefix name can only contain alphanumeric characters.'
        }

        ELSE{
            #Repeat
        }
    }
    return $vmName
}

function GetICONICSVersion {
    $ICONICSversion=''
    #Check ICONICS version
    while (-NOT ($ICONICSversion -eq '10.96.1' -OR $ICONICSversion -eq '10.96.2' -OR $ICONICSversion -eq '10.97')){
        IF ($ICONICSversion -and ($ICONICSversion -ne '10.96.1' -or $ICONICSversion -ne '10.96.2' -or $ICONICSversion -ne '10.97')){
            PrintError 'Enter 10.96.1 or 10.96.2 or 10.97'
        }

        write-host 'Enter ICONICS Suite version. ' -ForegroundColor Green -NoNewline
        write-host ' [10.96.1] ' -ForegroundColor white -BackgroundColor Black -NoNewline
        write-host ' ' -NoNewline
        write-host ' [10.96.2] ' -ForegroundColor white -BackgroundColor Black -NoNewline
        write-host ' '	 -NoNewline
        write-host ' [10.97] ' -ForegroundColor white -BackgroundColor Black -NoNewline
        wite-host ' '
        [string]$ICONICSversion=Read-Host 'ICONICS version'
    }
    return $ICONICSversion
}

function GetUserName {
    $username = ''
    #Check user name has no spaces
    while($username -eq '' -or $username -match ' '){
        #Has spaces
        IF ($username -match ' '){
            PrintError 'Username cannot have spaces.'
        }
        
        write-host 'Enter user name for initial admin account. ' -ForegroundColor Green -NoNewline
        write-host 'No spaces' -ForegroundColor Red -NoNewline
        write-host ' '
        [string]$username = Read-Host 'Username'
    }
    return $username
}

function GetPassword {
    $password=''
    write-host 'Enter a secure password ' -ForegroundColor Green -NoNewline
    write-host 'longer than 12 characters.' -ForegroundColor Red -NoNewline
    write-host ' '
            
    [string]$password=Read-Host 'Password' -MaskInput
    return $password
}

function AllowHTTP {
    $AllowHTTP=''
    while (-NOT($AllowHTTP -eq 'Y' -OR $AllowHTTP -eq 'N')){
        #Check input
        IF($AllowHTTP -and ($AllowHTTP -ne 'Y' -and $AllowHTTP -ne 'N')){
            PrintYesNoError
        }
        
        Write-Host 'Do you want to allow HTTP (TCP port 80) inbound access ?' -ForegroundColor Green -NoNewline
        PrintYesNoOption
    
        $AllowHTTP=Read-Host 'Allow HTTP Inbound?'
    }
    return $AllowHTTP
}

function AllowFWX {
    $AllowFWX=''
    while (-NOT($AllowFWX -eq 'Y' -OR $AllowFWX -eq 'N')){
        #Check input
        IF($AllowFWX -and ($AllowFWX -ne 'Y' -and $AllowFWX -ne 'N')){
            PrintYesNoError
        }

        Write-Host 'Do you want to allow FWX (TCP port 8778) inbound access ?' -ForegroundColor Green -NoNewline
        PrintYesNoOption

        $AllowFWX=Read-Host 'Allow FWX Inbound?'
    }
    return $AllowFWX
}

function ConfirmContinue {
    $continue=''
    while (-NOT($continue -eq 'Y' -OR $continue -eq 'N')){
        # Check confirmation
        IF($continue -and($continue -ne 'Y' -and $continue -ne 'N')){
            PrintYesNoError
        }

        Write-Host 'Do you want to continue? ' -ForegroundColor Green -NoNewline
        PrintYesNoOption
        [string]$continue=Read-Host 'Continue?'
    }
    return $continue
}
function ConfirmCreate {
    $confirmCreation=''
    while (-NOT($confirmCreation -eq 'Y' -OR $confirmCreation -eq 'N')){
        #Check Confirm Creation
        IF($confirmCreation -and($confirmCreation -ne 'Y' -and $confirmCreation -ne 'N')){
            PrintYesNoError
        }
    
        write-host 'Continue to create ? ' -ForegroundColor Green -NoNewline
        write-host 'Creation cannot be canceled until complete. ' -ForegroundColor red -NoNewline
        PrintYesNoOption
        [string]$confirmCreation=Read-Host 'Create?'   
    } 
    return $confirmCreation
}

IF(-NOT($Confirm -eq 'Y')){
#=======================================================================================================================
# Main Script
#=======================================================================================================================
#Introduction
write-host ' '
write-host ('='*200)
write-host ' '
write-host 'This script will create VMs with the latest ICONICS Azure Marketplace offers for the chosen version.'
write-host ' '
write-host 'All resources created by this script will be placed in the resource group of your choice.'
write-host 'A new resource group will be created if it doesn''t exist.'
write-host ' '
write-host 'VMs can be created in any region that is supported by your subscription.'
write-host ' '
write-host ('Your Az module version is: '+(get-installedmodule -name Az).Version+'. Minimum version to run this script is 5.4.0') -ForegroundColor Yellow -NoNewline
Write-Host ' '
write-host ' '
write-host ('='*200)
}
#=======================================================================================================================
# Subscription
#=======================================================================================================================

#Subscription set from input parameter
IF($SubscriptionName){
    PrintStatus ('Subscription set to '+$SubscriptionName)
    #Change subscription
    Set-AzContext -SubscriptionName $SubscriptionName
    $AzContext=Get-AzContext
    $owner=($AzContext.Account).Id
}
#Subscription no set from input parameter
ELSE {
    #Get current subscription
    $AzContext = Get-AzContext

    #Check if user logged in
    While(-NOT($AzContext)){
        #Ask to login
        Write-Host 'Please sign in to Azure with the following instructions.' -ForegroundColor Green -NoNewline
        Write-Host ' '
        Connect-AzAccount

        $AzContext = Get-AzContext
    }

    $owner=($AzContext.Account).Id

    #Confirm Subscription
    write-host 'Your current subscription is ' -foregroundcolor green -NoNewline
    Write-Host $AzContext.Subscription.Name -ForegroundColor Yellow -NoNewline
    Write-Host ' '

    #Ask if user wants to change subscription
    $changeSubscription = ChangeSubscription

    #Change subscription
    IF($changeSubscription -eq 'Y'){
        write-host 'Enter the name of the subscription to use.' -foregroundcolor green -NoNewline
        write-host ' '
        [string]$newSubscriptionName = Read-Host 'Subscription Name'
        
        write-host '~~ Changing subscription ~~' -ForegroundColor Yellow -NoNewline
        Write-Host ' '

        #Change subscription
        Set-AzContext -SubscriptionName $newSubscriptionName
        
        #Confirm subscription change
        $AzContext = Get-AzContext
        write-host 'Subscription changed to ' -foregroundcolor green -NoNewline
        write-host $AzContext.Subscription.Name -ForegroundColor Yellow -NoNewline
        Write-Host ' '
    }

    #Use current subscription
    ELSE {
        write-host 'Using current subscription ' -foregroundcolor green -NoNewline
        write-host $AzContext.Subscription.Name -ForegroundColor Yellow -NoNewline
        Write-Host ' '
    }
    $SubscriptionName=$AzContext.Subscription.Name
}

#=======================================================================================================================
# Resource Group
#=======================================================================================================================
#Initialize setRegion to True to ask for region
[bool]$setRegion=$true

#Initialize checkVMexist to False to skip checking if VM exists
[bool]$checkVMexist=$false

#Initialize vnetExist to False to create new VNet
[bool]$vnetExist=$false

#Initialize resourceGroupExist to False to create resource group
[bool]$resourceGroupExist=$false

#Resource group name set from input parameter
IF($ResourceGroupName){
    #Resource header
    PrintStatus ('Resource group is set to '+$ResourceGroupName)
    $resourceGroupName=$ResourceGroupName

    #Don't need to set resource group name since its pre-provided from parameter
    [String]$setResourceGroupName = 'N'

    #Set virtual network name
    $virtualNetworkName=$resourceGroupName+'-vnet'
    
    #Check if resource group exists
    Write-Host '~~ Checking if resource group exists ~~' -ForegroundColor Yellow -NoNewline
    Write-Host ' '
    $resourcegroups = Get-AzResourceGroup
            
    #Resource group exists. Use existing one and check VNet
    IF ($resourcegroups.ResourceGroupName -contains $resourceGroupName){
        $resourceGroupExist=$true
         #Check if VNet exist
        $vnet = Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName
        IF($vnet.name -contains $virtualNetworkName){
            $vnetExist=$true
        }
        ELSE {
            $vnetExist=$false
        }
        
        #Set $setRegion to false to skip region question since resource group exists.
        $setRegion=$false
        
        #Set $checkVMexist to True to check if VM exist in existing resource group.
        $checkVMexist=$true
        
        Write-Host $resourceGroupName'resource group exists.'
    } 
    #Resource group doesn't exist. Move on.	
    ELSE {
        
        #Tell user resource group is good
        write-host 'New resource group ' -NoNewline
        write-host $resourceGroupName -ForegroundColor Yellow -NoNewline
        write-host ' will be created.' -NoNewline
        write-host ' '
        #Exit while loop
        $setResourceGroupName='N'
    }
}
#No resource group set from input parameter
ELSE{
    #Get resource group
    write-host ('='*200) -ForegroundColor Green
    
    #Set resource group since its not pre-provided from parameter
    [String]$setResourceGroupName = 'Y'
}

#Keep asking for resource group name if user doesn't set $setResourceGroupName to N
while($setResourceGroupName -eq 'Y'){
    #Initialize resourceGroupExist to false, setRegion to true, and checkVMexist to false assuming resourcegroup doesn't exist.
    $resourceGroupExist=$false
    $setRegion=$true
    $checkVMexist=$false

    #Initial ask for resource group name
    $resourceGroupName=GetResourceGroupName

    #Set virtual network name
    $virtualNetworkName=$resourceGroupName+'-vnet'

    #Check if resource group exists
    Write-Host '~~ Checking if resource group exists ~~' -ForegroundColor Yellow -NoNewline
    Write-Host ' '

    $resourcegroups = Get-AzResourceGroup
            
    #Resource group exists. Ask user if they want to change.
    IF ($resourcegroups.ResourceGroupName -contains $resourceGroupName){
        $resourceGroupExist=$true

        #Check if VNet exist
        $vnet = Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName
        IF($vnet.name -contains $virtualNetworkName){
            $vnetExist=$true
        }
        ELSE {
            $vnetExist=$false
        }

        #Set $setRegion to false to skip region question since resource group exists.
        $setRegion=$false

        #Set $checkVMexist to True to check if VM exist in existing resource group.
        $checkVMexist=$true

        #Ask user if they want to change resource group name.   
        $setResourceGroupName = ChangeResourceGroupName
    } 
    #Resource group doesn't exist. Move on.	
    ELSE {
        #Tell user resource group is good
        write-host 'New resource group ' -NoNewline
        write-host $resourceGroupName -ForegroundColor Yellow -NoNewline
        write-host ' will be created.' -NoNewline
        write-host ' '

        #Exit while loop
        $setResourceGroupName='N'
    }
}

#=======================================================================================================================
# Azure Region
#=======================================================================================================================
#If location parameter is not provided, then run the usual GUI stuff
IF(!$Location){
    #Get Azure region
    write-host ('='*200) -ForegroundColor Green
    #New resource group is to be created. Ask for region.
    IF($setRegion -eq $true){	
        #Call GetAzureRegion
        $location=GetAzureRegion
    } 

    #Resource group already exist. Get resource group region and ask if user wants to continue.
    ELSE {
        #Get existing resource group Azure region
        [string]$location=(Get-AzResourceGroup -Name $resourceGroupName).Location

        Write-Host 'Azure region of ' -NoNewline
        Write-Host $resourceGroupName -ForegroundColor Yellow -NoNewline
        Write-Host ' is ' -NoNewline
        Write-Host $location -ForegroundColor Yellow -NoNewline
        Write-Host '. '

        #Ask user if they want to continue
        $continue=ConfirmContinue

        #Exit if user doesn't want to continue
        IF($continue -eq 'N'){
            PrintError 'Restart the script' $false
            exit
        } 
        ELSE {
            #Continue
        }
    }
}
#Location parameter provided
ELSE{
    $location=$Location
}

#=======================================================================================================================
# VM Count
#=======================================================================================================================
#Number of VMs not provided by parameter
IF(!$VMCount){
    #Get # of VMs
    write-host ('='*200) -ForegroundColor Green
    write-host 'Enter number of VMs to create.' -foregroundcolor green -NoNewline
    write-host ' '
    [int]$numberVMs=Read-Host '# of VMs'
}
#VM count provided by input parameter
ELSE{
    [int]$numberVMs=$VMCount
}

#=======================================================================================================================
# VM Size
#=======================================================================================================================
#VM size not provided by parameter
IF(!$VMSize){
    #Get VM size
    write-host ('='*200) -ForegroundColor Green

    #Initial GetVMSize
    $vmSize=GetVMsize
}
#VM size provided by input parameter
ELSE {
    $vmSize=$VMSize
}

#=======================================================================================================================
# SSD
#=======================================================================================================================
#SSD not provided by parameter
IF(!$UseSSD){
    write-host ('='*200) -ForegroundColor Green

    $SSD=GetSSDOption
}
#SSD provided by parameter
ELSE{
    $SSD=$UseSSD
}

#=======================================================================================================================
# VM Prefix Name
#=======================================================================================================================
#VM prefix not provided by parameter
IF(!$VMPrefix){
    #Get VM prefix
    write-host ('='*200) -ForegroundColor Green
    
    #Initial Get VM Name
    $vmName=GetVMName
}
#VM prefix provided by parameter
ELSE{
    $vmName=$VMPrefix
}

#Existing resource group. Check if there are resources with user given prefix.
IF($checkVMexist -eq $true){
    Write-Host '~~ Checking for VMs with the same prefix ~~' -ForegroundColor Yellow -NoNewline
    Write-Host ' '
    $VMs=Get-AzResource -ResourceGroupName $resourceGroupName -ResourceType 'Microsoft.Compute/virtualMachines' -Name ($vmName+'*') 
    #There are resources containing user given prefix.
    IF($VMs){
        #Get VM count to increment index later
        $VMsCount=$VMs.count
        write-host 'Found ' -NoNewline
        write-host $VMsCount -ForegroundColor Yellow -NoNewline
        write-host ' VM(s) with ' -NoNewline
        write-host $vmName -foregroundcolor Yellow -NoNewline
        write-host ' prefix.'
    } 
    #No existing resources in exisitng resource group as user given prefix. OK to continue
    ELSE {
        #Continue
        $VMsCount=0
    }
} 
ELSE {
    #Continue
    $VMsCount=0
    $checkVMexist=$false
}

#=======================================================================================================================
# ICONICS Version
#=======================================================================================================================
#ICONICS version not provided by parameter
IF(!$ICONICSversion){
    #Get ICONICS version
    write-host ('='*200) -ForegroundColor Green

    #Call GetICONICSVersion
    $ICONICSversion=GetICONICSVersion
}
#ICONICS version provided by parameter
ELSE{
    $ICONICSversion=$ICONICSversion
}

#=======================================================================================================================
# User Name
#=======================================================================================================================
#User name not provided by parameter
IF(!$Username){
    #Get user name
    write-host ('='*200) -ForegroundColor Green

    #Call GetUserName
    $username = GetUserName
}
#User name provided by parameter
ELSE{
    $username=$Username
}

#=======================================================================================================================
# Password
#=======================================================================================================================
#Password RegEx
$pwRegEx= '(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])(?=.*[\W_])\S{12,72}'

#Password not provided by parameter
IF(!$Password){
    #Initialize $passwordMatch
    write-host ('='*200) -ForegroundColor Green
    $passwordMatch=$false

    #Ask for password if $passwordMatch is false
    while($passwordMatch -eq $false){	
        #Get password	
        $password=GetPassword

        #Check password length
        while (-NOT($password -match $pwRegEx)){

            #Password too short
            IF ($password.Length -lt 12){
                PrintError 'Password has to be longer than 12 characters.'                   
                $password=GetPassword
            }

            #Password not complex enough
            PrintError 'Password is not secure.'

            write-host 'Password MUST have lower case ' -ForegroundColor Green -NoNewline
            write-host '[a-z]' -NoNewline
            write-host ' AND upper case '  -ForegroundColor Green -NoNewline
            write-host '[A-Z]' -NoNewline
            write-host ' characters AND a number '  -ForegroundColor Green -NoNewline
            write-host '[0-9]' -NoNewline
            write-host ' AND a special character '  -ForegroundColor Green -NoNewline
            write-host '[@#$%!&...]' -NoNewline
            Write-Host ' '

            $password=GetPassword
        }

        #Confirm password	
        write-host 'Confirm password.' -ForegroundColor Green -NoNewline
        write-host ' '
            
        [string]$passwordconfirm=Read-Host 'Password' -MaskInput
            
        #Check password match
        IF ($password -ne $passwordconfirm){
            PrintError 'Password does not match.'
            PrintError 'Re-enter passwords or use Ctrl+C to exit and re-run the script.' $false      

            $passwordMatch=$false
        } 
        #Passwords match, continue
        ELSE {
            #Continue
            $passwordMatch=$true
        }
    }
}
#Password provided by parameter
ELSE{
    PrintStatus ('Password set by input parameter')
    $password=$Password

    Write-Host '~~ Checking password length and complexity ~~' -ForegroundColor Yellow -NoNewline
    Write-Host ' '

    #Password too short
    IF ($password.Length -lt 12){
        PrintError 'Password from parameter has to be longer than 12 characters.'                   
        exit
    }

    #Password not complex enough
    IF (-NOT($password -match $pwRegEx)){
        #Password not complex enough
        PrintError 'Password from parameter is not secure.'

        write-host 'Password MUST have lower case ' -ForegroundColor Green -NoNewline
        write-host '[a-z]' -NoNewline
        write-host ' AND upper case '  -ForegroundColor Green -NoNewline
        write-host '[A-Z]' -NoNewline
        write-host ' characters AND a number '  -ForegroundColor Green -NoNewline
        write-host '[0-9]' -NoNewline
        write-host ' AND a special character '  -ForegroundColor Green -NoNewline
        write-host '[@#$%!&...]' -NoNewline
        Write-Host ' '

        exit
    }
}

#=======================================================================================================================
# HTTP and FWX ports
#=======================================================================================================================
#Ask for HTTP and FWX port allow if VNet doesn't exist
IF($vnetExist -eq $false){
    #AllowHTTP not provided by parameter
    IF(!$AllowHTTP){
        #Allow HTTP
        write-host ('='*200) -ForegroundColor Green
        $AllowHTTP=AllowHTTP
    }
    #AllowHTTP provided by password
    ELSE{
        #Check if parameter value is valid
        IF($AllowHTTP -and ($AllowHTTP -ne 'Y' -and $AllowHTTP -ne 'N')){
            PrintYesNoError
            $AllowHTTP=AllowHTTP
        }
    }

    #AllowFWX not provided by parameter
    IF(!$AllowFWX){
        #Allow FWX
        write-host ('='*200) -ForegroundColor Green
        $AllowFWX=AllowFWX
    }
    #AllowFWX provided by parameter
    ELSE{
        #Check if parameter value is valid
        IF($AllowFWX -and ($AllowFWX -ne 'Y' -and $AllowFWX -ne 'N')){
            PrintYesNoError
            $AllowFWX=AllowFWX
        }
    }
}
ELSE {
    #Continue
}

#=======================================================================================================================
# Confirmation
#=======================================================================================================================
IF(!$Confirm -or $Confirm -ne 'Y'){
    #Confirm to proceed
    PrintStatus 'Confirm VM creation parameters:'

    PrintConfirmationEntry 'Subscription:' $AzContext.Subscription.Name
    PrintConfirmationEntry 'Resource group name:' $resourceGroupName
    PrintConfirmationEntry 'Azure region:' $location
    PrintConfirmationEntry 'Number of VMs:' $numberVMs
    PrintConfirmationEntry 'VM size:' $vmSize
    PrintConfirmationEntry 'SSD:' (PrintYESNO($SSD))
    PrintConfirmationEntry 'VM prefix name:' $vmName
    PrintConfirmationEntry 'ICONICS version:' $ICONICSversion
    PrintConfirmationEntry 'Username:' $username

    IF($vnetExist -eq $false){
        PrintConfirmationEntry 'Allow HTTP Inbound:' (PrintYESNO($AllowHTTP))
        PrintConfirmationEntry 'Allow FWX Inbound:' (PrintYESNO($AllowFWX))
    }

    write-host ('='*200)
    write-host ' '

#=======================================================================================================================
# Confirm creation
#=======================================================================================================================

    $confirmCreation=ConfirmCreate
}
ELSE{
    $confirmCreation=$Confirm
}

#Exit if $confirmCreateion is N
IF($confirmCreation -eq 'N'){
    PrintError 'Re-run the script.' $false
    exit
}

#======================================================================================================================
# Create resources
#======================================================================================================================
ELSE {
    #Set ICONICS Version
    $ICONICSversionTag=$ICONICSversion
    $ICONICSversion=$ICONICSversion.replace( '.', '')
    
    #Base Parameters
    $ipSetup = 'Static'
    #$virtualNetworkName = $resourceGroupName+'-vnet'
    $virtualMachineName = $vmName
    $virtualMachineSize = 'Standard_'+$vmSize

    #Set sleep timers
    $NICCreateDuration = 3*$numberVMs

    #Set ICONICS SKU
    $iconicsSKU='iconics-suite-'+$ICONICSversion

    #=======================================================================================================================
    # Create resource group, subnet, nsg, vnet, whichever doesn't exist
    #=======================================================================================================================
    IF ($resourceGroupExist -eq $true){
        PrintStatus($resourceGroupName+' exists.')
                
        #Create vnet if $vnetExist is false
        IF($vnetExist -eq $false) {
            #Create virtual network
            PrintStatus ('Creating Virtual Network: '+$virtualNetworkName)
                        
            #Security rules
            $rdpRule = New-AzNetworkSecurityRuleConfig -Name rdp-inbound-rule -Description 'Allow RDP Inbound' -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389
            $httpRule = New-AzNetworkSecurityRuleConfig -Name http-inbound-rule -Description 'Allow HTTP Inbound' -Access Allow -Protocol Tcp -Direction Inbound -Priority 101 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80
            $FWXRule = New-AzNetworkSecurityRuleConfig -Name icoFWX-inbound-rule -Description 'Allow ICONICS FWX Inbound' -Access Allow -Protocol Tcp -Direction Inbound -Priority 102 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8778

            #Both HTTP & FWX allowed
            IF (($AllowHTTP -eq 'Y') -and ($AllowFWX -eq 'Y')){
                $networkSecurityGroup = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name ($resourceGroupName+'-nsg') -SecurityRules $rdpRule,$httpRule,$FWXRule    
            }
            #Only HTTP allowed
            ELSEIF (($AllowHTTP -eq 'Y') -and ($AllowFWX -eq 'N')){
                $networkSecurityGroup = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name ($resourceGroupName+'-nsg') -SecurityRules $rdpRule, $httpRule
            }
            #Only FWX allowed
            ELSEIF (($AllowHTTP -eq 'N') -and ($AllowFWX -eq 'Y')){
                $networkSecurityGroup = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name ($resourceGroupName+'-nsg') -SecurityRules $rdpRule,$FWXRule
            }
            #Both HTTP & FWX NOT allowed
            ELSE {
                $networkSecurityGroup = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name ($resourceGroupName+'-nsg') -SecurityRules $rdpRule
            }

            #NSG, Subnet, VNet
            $subnet = New-AzVirtualNetworkSubnetConfig -Name subnet -AddressPrefix '10.0.1.0/24' -NetworkSecurityGroup $networkSecurityGroup
            $vnet = New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix '10.0.0.0/16' -Subnet $subnet
        }
        ELSE {
            #Continue
        }   
    }

    #=======================================================================================================================
    # Create new resource group, rdp, nsg, subnet, vnet
    #=======================================================================================================================
    Else {
        PrintStatus ('Creating Resource Group: '+$resourceGroupName)
        
        #Create resource group
        New-AzResourceGroup -Name $resourceGroupName -Location $location -Tag @{'Owner'=$owner}
        
        #Create virtual network
        PrintStatus ('Creating Virtual Network: '+$virtualNetworkName)      
        
        #Security rules
        $rdpRule = New-AzNetworkSecurityRuleConfig -Name rdp-inbound-rule -Description 'Allow RDP Inbound' -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389
        $httpRule = New-AzNetworkSecurityRuleConfig -Name http-inbound-rule -Description 'Allow HTTP Inbound' -Access Allow -Protocol Tcp -Direction Inbound -Priority 101 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80
        $FWXRule = New-AzNetworkSecurityRuleConfig -Name icoFWX-inbound-rule -Description 'Allow ICONICS FWX Inbound' -Access Allow -Protocol Tcp -Direction Inbound -Priority 102 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8778

        #Both HTTP & FWX allowed
        IF (($AllowHTTP -eq 'Y') -and ($AllowFWX -eq 'Y')){
            $networkSecurityGroup = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name ($resourceGroupName+'-nsg') -SecurityRules $rdpRule,$httpRule,$FWXRule    
        }
        #Only HTTP allowed
        ELSEIF (($AllowHTTP -eq 'Y') -and ($AllowFWX -eq 'N')){
            $networkSecurityGroup = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name ($resourceGroupName+'-nsg') -SecurityRules $rdpRule, $httpRule
        }
        #Only FWX allowed
        ELSEIF (($AllowHTTP -eq 'N') -and ($AllowFWX -eq 'Y')){
            $networkSecurityGroup = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name ($resourceGroupName+'-nsg') -SecurityRules $rdpRule,$FWXRule
        }
        #Both HTTP & FWX NOT allowed
        ELSE {
            $networkSecurityGroup = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name ($resourceGroupName+'-nsg') -SecurityRules $rdpRule
        }

        #NSG, Subnet, VNet
        $subnet = New-AzVirtualNetworkSubnetConfig -Name subnet -AddressPrefix '10.0.1.0/24' -NetworkSecurityGroup $networkSecurityGroup
        $vnet = New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix '10.0.0.0/16' -Subnet $subnet
    }

    #=======================================================================================================================
    # Encrypt password
    #=======================================================================================================================
    $tmp = $password
    $pass = ConvertTo-SecureString $tmp -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($username, $pass);

    #=======================================================================================================================
    # Create VM Config Object
    #=======================================================================================================================
    $VirtualMachines = @()
    For($i=0; $i -lt $numberVMs; $i++){
        PrintStatus ('Creating VM Object: '+($virtualMachineName + '-' + ($i+1+$VMsCount).ToString()))       
        $VirtualMachines += New-AzVMConfig -VMName ($virtualMachineName + '-' + ($i+1+$VMsCount).ToString()) -VMSize $virtualMachineSize
    }

    #=======================================================================================================================
    # Create Public IPs
    #=======================================================================================================================
    For($i=0; $i -lt $numberVMs; $i++){
        PrintStatus ('Creating IP: '+($VirtualMachineName.ToLower() + '-' + ($i+1+$VMsCount).ToString() + '-ip'))
        New-AzPublicIpAddress -Name ($VirtualMachineName.ToLower() + '-' + ($i+1+$VMsCount).ToString() + '-ip') -ResourceGroupName $resourceGroupName -Location $location -AllocationMethod $ipSetup -DomainNameLabel ($resourceGroupName.ToLower()+'-'+$VirtualMachineName.ToLower() + '-' + ($i+1+$VMsCount).ToString()) -AsJob
    }

    WaitJob 'New-AzPublicIpAddress'

    #=======================================================================================================================
    # Get Public IPs
    #=======================================================================================================================
    $publicIps = @()
    For($i=0; $i -lt $numberVMs; $i++){
        $publicIps += Get-AzPublicIpAddress -Name ($VirtualMachineName.ToLower() + '-' + ($i+1+$VMsCount).ToString() + '-ip') -ResourceGroupName $resourceGroupName
    }
    
    #=======================================================================================================================
    # Create NICs
    #=======================================================================================================================
    $nics = @()
    For($i=0; $i -lt $numberVMs; $i++){
        PrintStatus ('Creating NIC: '+($VirtualMachineName.ToLower() + '-' + ($i+1+$VMsCount).ToString() + '-nic'))
        New-AzNetworkInterface -Name ($VirtualMachineName.ToLower() + '-' + ($i+1+$VMsCount).ToString() + '-nic') -ResourceGroupName $resourceGroupName -Location $location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $publicIps[$i].Id -AsJob
    }

    WaitJob 'New-AzNetworkInterface'

    #=======================================================================================================================
    # Get NICs
    #=======================================================================================================================
    For($i=0; $i -lt $numberVMs; $i++){
        $nics += Get-AzNetworkInterface -Name ($VirtualMachineName.ToLower() + '-' + ($i+1+$VMsCount).ToString() + '-nic') -ResourceGroupName $resourceGroupName
    }

    #=======================================================================================================================
    # Add VM definitions to VM object
    #=======================================================================================================================
    For ($i=0; $i -lt $numberVMs; $i++){
        #Set OS Type and Credentials
        $VirtualMachines[$i] = Set-AzVMOperatingSystem -VM $VirtualMachines[$i] -Windows -ComputerName ($virtualMachineName + '-' + ($i+1+$VMsCount).ToString()) -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
        
        #Use HDD if SSD option is N
        If ($SSD -eq 'N'){
            $VirtualMachines[$i] = Set-AzVMOSDisk -VM $VirtualMachines[$i] -Windows -CreateOption FromImage -StorageAccountType 'Standard_LRS' 
        }
                
        #Set NIC
        $VirtualMachines[$i] = Add-AzVMNetworkInterface -VM $VirtualMachines[$i] -Id $nics[$i].Id
        
        #Set Source Image to Marketplace image
        $VirtualMachines[$i] = Set-AzVMSourceImage -VM $VirtualMachines[$i] -PublisherName 'iconics' -Offer $iconicsSKU -Skus $iconicsSKU -Version latest
            
        #Set VM Plan
        $VirtualMachines[$i] = Set-AzVMPlan -VM $VirtualMachines[$i] -Publisher 'iconics' -Product $iconicsSKU -Name $iconicsSKU
            
        #Disable Boot Diagnostics
        $VirtualMachines[$i] = Set-AzVMBootDiagnostic -VM $VirtualMachines[$i] -Disable
    }

    #=======================================================================================================================
    # Create VM
    #=======================================================================================================================    
    $VMDNS=@()
    For($i=0; $i -lt $numberVMs; $i++){
        PrintStatus ('Creating VM: '+($virtualMachineName + '-' + ($i+1+$VMsCount).ToString()))
        Get-AzMarketplaceTerms -Publisher 'iconics' -Product $iconicsSKU -Name $iconicsSKU | Set-AzMarketplaceTerms -Accept
        New-AzVm -ResourceGroupName $resourceGroupName -Location $location -VM $VirtualMachines[$i] -Tag @{'Owner'=$owner;'ICONICS Version'=$ICONICSversionTag} -AsJob

        $VMDNS += ($publicIps[$i].dnssettings).Fqdn
        
        PrintStatus ('VM is still being created. Wait for final complete message before attempting to access VM.')
    }

    IF(!$AsJob -or $AsJob -ne 'Y'){
        WaitJob 'New-AzVm'

        #=======================================================================================================================
        # Create Complete
        #=======================================================================================================================
        Write-Host ('='*200)
        write-host 'VM Creation Complete.'
        Write-Host ('-'*200)

        PrintConfirmationEntry 'Username:' $username
        Write-Host ('-'*200)
        write-host 'VM DNS Addresses:'
        For($i=0;$i -lt $numberVMs; $i++){
            PrintConfirmationEntry ($virtualMachineName + '-' + ($i+1+$VMsCount).ToString()+':') $VMDNS[$i]
        }
        
        IF($Confirm){
            #Continue
        }
        ELSE{
            write-host ('-' *200) -ForegroundColor Green -NoNewline
            write-host ' '
            write-host 'Parameterized command:' -ForegroundColor Green -NoNewline
            write-host ' '
            write-host './New-IcoAzVM.ps1 -SubscriptionName ''' -NoNewline
            write-host $AzContext.Subscription.Name -NoNewline
            write-host ''' -ResourceGroupName ''' -NoNewline 
            write-host $resourceGroupName -NoNewline
            write-host ''' -Location ''' -nonewline 
            write-host $location -nonewline
            write-host ''' -VMCount ''' -nonewline
            write-host $numberVMs -nonewline
            write-host ''' -VMSize ''' -nonewline
            write-host $vmSize -nonewline
            write-host ''' -UseSSD ''' -nonewline
            write-host $SSD -nonewline 
            write-host ''' -VMPrefix ''' -nonewline
            write-host $vmName -nonewline
            write-host ''' -ICONICSversion ''' -nonewline
            write-host $ICONICSversion -nonewline
            write-host ''' -Username ''' -nonewline
            write-host $username -nonewline
            write-host ''' -Password ''' -nonewline
            write-host $password -nonewline
            IF($vnetExist -eq $false){
                write-host '''' -NoNewline
                write-host '-AllowHTTP ''' -nonewline
                write-host $AllowHTTP -nonewline
                write-host ''' -AllowFWX ''' -nonewline
                write-host $AllowFWX -nonewline
                write-host ''''
            }
            ELSE{
                write-host ''''
            }
            Write-Host ('='*200)
        }
    }
}