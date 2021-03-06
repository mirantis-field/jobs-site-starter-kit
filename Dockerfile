# escape=`
FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8-windowsservercore-ltsc2019
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

RUN Remove-Website 'Default Web Site'

RUN Enable-WindowsOptionalFeature `
    -Online `
    -All `
    -FeatureName `
    IIS-ApplicationDevelopment, `
    IIS-CommonHttpFeatures, `
    IIS-DefaultDocument, `
    IIS-DirectoryBrowsing, `
    IIS-HealthAndDiagnostics, `
    IIS-HttpCompressionStatic, `
    IIS-HttpErrors, `
    IIS-HttpLogging, `
    IIS-ISAPIExtensions, `
    IIS-ISAPIFilter, `
    IIS-Performance, `
    IIS-RequestFiltering, `
    IIS-Security, `
    IIS-StaticContent, `
    IIS-WebServer, `
    IIS-WebServerRole

# Expose port(s) from website's bindings.
EXPOSE 8000
EXPOSE 8080
EXPOSE 44300

# Create and configure app pools
RUN Import-Module WebAdministration ; `
    New-Item -Path 'IIS:\AppPools\JobsAppPool' ; `
    Set-ItemProperty -Path 'IIS:\AppPools\JobsAppPool' -Name processModel -Value @{identitytype='LocalSystem'}

# Copy physical paths
COPY Jobs C:\Jobs

# Copy SSL certificates for website bindings.
COPY c0562a7b889037523da4c76cdd39933046132da3.pfx C:\c0562a7b889037523da4c76cdd39933046132da3.pfx

# Set ACLs
RUN $path='C:\Jobs' ; `
    $acl = Get-Acl $path ; `
    $newOwner = [System.Security.Principal.NTAccount]('BUILTIN\IIS_IUSRS') ; `
    $acl.SetOwner($newOwner) ; `
    dir -r $path | Set-Acl -aclobject  $acl

# Initialize website
RUN New-Item -Path 'C:\Jobs' -Type Directory -Force ; `
    New-Website -Name 'Jobs' -PhysicalPath 'C:\Jobs' -ApplicationPool 'JobsAppPool' -IPAddress '*' -Port 8080 -Force ; `
    New-WebBinding -Name 'Jobs' -IPAddress '*' -Port 8000 -Protocol 'http' ; `
    New-WebBinding -Name 'Jobs' -IPAddress '*' -Port 44300 -Protocol 'https' ; `
    $cert = Import-PfxCertificate -FilePath 'c0562a7b889037523da4c76cdd39933046132da3.pfx' Cert:\LocalMachine\WebHosting ; `
    New-Item -path IIS:\SslBindings\0.0.0.0!44300 -value $cert

# Configure Remote Administration in IIS.
RUN Install-WindowsFeature Web-Mgmt-Service ; `
    New-ItemProperty -Path HKLM:\software\microsoft\WebManagement\Server -Name EnableRemoteManagement -Value 1 -Force ; `
    Set-Service -Name wmsvc -StartupType automatic ; `
    net user 'Docker' 'BuildShip&Run' /add ; `
    net localgroup administrators Docker /add

# Configure LogMonitor
# https://github.com/microsoft/windows-container-tools/tree/master/LogMonitor
ADD https://github.com/microsoft/windows-container-tools/releases/download/v1.0/LogMonitor.exe c:\LogMonitor\LogMonitor.exe
ADD LogMonitorConfig.json c:\LogMonitor\
SHELL ["C:\\LogMonitor\\LogMonitor.exe", "powershell.exe"]
 
# Start IIS Remote Management and monitor IIS
ENTRYPOINT Start-Service W3SVC; C:\\ServiceMonitor.exe w3svc
