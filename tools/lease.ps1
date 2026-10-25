# Board leases for a board shared by several programs at once: dot-source this
# file, then Get-BoardLease / Release-BoardLease around every upload and run.
# The shared lease script is PM51_LEASE_SCRIPT, or the lab's usual one; with
# neither, the board is taken to be yours alone and the calls do nothing.
$pm51LeaseScript = if ($env:PM51_LEASE_SCRIPT) { $env:PM51_LEASE_SCRIPT } else { 'C:\PMFBuild\board-leases\lease.ps1' }
if (Test-Path $pm51LeaseScript) {
    . $pm51LeaseScript
} else {
    function Get-BoardLease { param([string]$Port, [string]$Owner, [int]$Minutes) return $Port }
    function Release-BoardLease { param($Lease) }
}
