function Share-PartialScreen {
    [CmdletBinding(DefaultParameterSetName='Preset')]
    Param(
        [Parameter(Mandatory = $false)]
        [string] $preset,

        [Parameter(Mandatory = $false)]
        [int] $Width = 1920,
        
        [Parameter(Mandatory = $false)]
        [int] $Height = 1080,

        [Parameter(Mandatory = $false)]
        [int] $TaskbarOffsetX = 0,

        [Parameter(Mandatory = $false)]
        [int] $TaskbarOffsetY = 0
    )

    switch ($preset) {
        "720p" { 
            $Width = 1280
            $Height = 720
        }
        "1080p" { 
            $Width = 1920
            $Height = 1080
        }
    }

    $id = Start-Process -FilePath "C:\Program Files\VideoLAN\VLC\vlc.exe" -ArgumentList "screen:// --screen-left=$TaskbarOffsetX --screen-top=$TaskbarOffsetY --screen-fps=30 --live-caching=300 --screen-width=$Width --screen-height=$Height --no-embedded-video --no-video-deco --qt-start-minimized" -PassThru

    [reflection.assembly]::LoadWithPartialName("System.Windows.Forms")
    [reflection.assembly]::LoadWithPartialName("System.Drawing")

    $pen = New-Object Drawing.Pen red
    $brushRed = New-Object Drawing.SolidBrush red
    $brushWhite = New-Object Drawing.SolidBrush white
    $font = New-Object Drawing.Font "Arial", 14

    $form = New-Object Windows.Forms.Form
    $form.TransparencyKey = $form.BackColor
    $form.WindowState = 'Maximized'
    $form.FormBorderStyle = 'None'
    $form.TopMost = $true

    $formGraphics = $form.createGraphics()

    $form.add_paint(
        {
            $formGraphics.DrawRectangle($pen, $TaskbarOffsetX, $TaskbarOffsetY, $Width + 1, $Height + 1)
            $formGraphics.FillRectangle($brushRed, $Width + $TaskbarOffsetX + 1, $TaskbarOffsetY, 60, 30)
            $formGraphics.DrawString("close", $font, $brushWhite, $Width + $TaskbarOffsetX + 5, $TaskbarOffsetY + 3)
        }
    )

    $form.Add_Click({$form.Close()})
    $form.ShowDialog()   # display the dialog

    Stop-Process $id
}