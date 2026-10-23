if ($Selftest) {
    "== cleanup"
    foreach ($c in $script:CleanItems) { '{0,-10} {1,10}' -f $c.Id, (Format-Size (Get-CleanSize $c)) }
    "== startup"
    foreach ($s in Get-StartupItems) {
        $cmd = "$($s.Command)"; if ($cmd.Length -gt 50) { $cmd = $cmd.Substring(0, 50) + '…' }
        '{0,-4} {1,-32} {2,-38} {3}' -f $(if ($s.On) { 'on' } else { 'off' }), $s.Name, $s.Label, $cmd
    }
    "== drivers"
    foreach ($d in Get-DriverInfo) {
        $urls = @($d.Buttons | ForEach-Object { $_[1] }) -join ' '
        '{0,-22} {1,-45} {2,-11} {3}' -f $d.Kind, $d.Title, $(if ($d.Date) { $d.Date.ToString('yyyy-MM-dd') } else { '-' }), $urls
    }
    Initialize-Items
    $script:Items | ForEach-Object { '{0,-40} {1,-13} {2,-7} {3}' -f $_.Id, $_.Cat, $_.Impact, $_.State }
    "items: $($script:Items.Count) of $($script:AllItems.Count)"
    "detected: " + (($script:Detected.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')
    "questions shown: " + (($script:Questions | Where-Object { Test-Question $_ } | ForEach-Object { $_.Id }) -join ', ')
    $ans = Get-Answers
    "answers: " + (($script:Questions | Where-Object { Test-Question $_ } | ForEach-Object { "$($_.Id)=$($ans[$_.Id])" }) -join ' ')
    "plan with default answers: $(Get-PlanCount $ans) changes"
    exit
}
