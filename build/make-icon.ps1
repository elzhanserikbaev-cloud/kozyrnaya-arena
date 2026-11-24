# Рисует icon.png 1024x1024 (карта-туз с пиками на фиолетовом фоне) для сборок Electron.
Add-Type -AssemblyName System.Drawing
$out = Join-Path $PSScriptRoot 'icon.png'
function New-Frame([int]$s) {
  $bmp = New-Object System.Drawing.Bitmap $s, $s
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
  $g.Clear([System.Drawing.Color]::Transparent)
  function RR($x,$y,$w,$h,$r){ $p=New-Object System.Drawing.Drawing2D.GraphicsPath; $p.AddArc($x,$y,$r,$r,180,90); $p.AddArc($x+$w-$r,$y,$r,$r,270,90); $p.AddArc($x+$w-$r,$y+$h-$r,$r,$r,0,90); $p.AddArc($x,$y+$h-$r,$r,$r,90,90); $p.CloseFigure(); $p }
  $bg = RR 0 0 ($s-1) ($s-1) ($s*0.28)
  $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point 0,0),(New-Object System.Drawing.Point $s,$s),[System.Drawing.Color]::FromArgb(74,52,110),[System.Drawing.Color]::FromArgb(26,17,40))
  $g.FillPath($br,$bg)
  $cw=$s*0.56; $ch=$s*0.76; $cx=($s-$cw)/2; $cy=($s-$ch)/2
  $g.TranslateTransform($s/2,$s/2); $g.RotateTransform(-8); $g.TranslateTransform(-$s/2,-$s/2)
  $card = RR $cx $cy $cw $ch ($s*0.1)
  $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(228,174,80))),$card)
  $inner = RR ($cx+$s*0.025) ($cy+$s*0.025) ($cw-$s*0.05) ($ch-$s*0.05) ($s*0.08)
  $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(248,240,224))),$inner)
  $sf = New-Object System.Drawing.StringFormat; $sf.Alignment='Center'; $sf.LineAlignment='Center'
  $ink = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(36,30,47))
  $f1 = New-Object System.Drawing.Font('Segoe UI Symbol', [single]($s*0.36), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
  $g.DrawString([string][char]0x2660, $f1, $ink, (New-Object System.Drawing.RectangleF $cx,($cy+$s*0.06),$cw,$ch), $sf)
  if ($s -ge 48) {
    $f2 = New-Object System.Drawing.Font('Arial Black', [single]($s*0.13), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $g.DrawString('A', $f2, (New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(195,58,80))), [single]($cx+$s*0.04), [single]($cy+$s*0.02))
  }
  $g.Dispose()
  $ms = New-Object System.IO.MemoryStream; $bmp.Save($ms,[System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  ,$ms.ToArray()
}
[IO.File]::WriteAllBytes($out,(New-Frame 1024))
"icon: $out"
