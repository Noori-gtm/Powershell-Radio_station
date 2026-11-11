
Clear-Host

# ORDNER
$Desktop = "C:\Users\mobeen.noori\OneDrive - Regionales Ausbildungszentrum Au\Desktop"
$Quelle = "$Desktop\Originaldateien"
$Ziel = "$Desktop\Musiksammlung"
$Bitrate = "320k"

# ORDNER AUSWÄHLEN
$Ordner = @(Get-ChildItem -Path $Quelle -Directory | Sort-Object Name)

Write-Host "Welchen Ordner möchtest du konvertieren?"

for ($i = 0; $i -lt $Ordner.Count; $i++) {
    Write-Host "$($i + 1) - $($Ordner[$i].Name)"
}

$Wahl = Read-Host "Nummer eingeben"

if ($Wahl -notmatch '^\d+$' -or [int]$Wahl -lt 1 -or [int]$Wahl -gt $Ordner.Count) {
    Write-Host "Ungültige Auswahl!"
    return
}

$HauptOrdner = $Ordner[[int]$Wahl - 1].FullName

# METADATEN
$Artist = (Read-Host "Artist eingeben").Trim()
$Jahr = Read-Host "Jahr eingeben"
$Genre = Read-Host "Genre eingeben"

if ($Artist -eq "" -or $Artist -match '[\\/:*?"<>|]') {
    Write-Host "Ungültiger Artist!"
    return
}

$Album = $Artist

# ZIELORDNER ERSTELLEN
$ArtistOrdner = Join-Path $Ziel $Artist
$AlbumOrdner = Join-Path $ArtistOrdner $Album
$GesamtDatei = Join-Path $ArtistOrdner "$Album.mp3"

New-Item -ItemType Directory -Path $AlbumOrdner -Force | Out-Null

# AUDIOFORMATE
$Formate = @(".wav", ".flac", ".mp3", ".aac", ".m4a", ".ogg", ".opus", ".wma")

# DATEIEN EINLESEN
$Dateien = @(Get-ChildItem -Path $HauptOrdner -File -Recurse |
    Where-Object { $_.Extension.ToLower() -in $Formate })

# NUR DATEIEN MIT TRACKNUMMER VERWENDEN
$Dateien = @($Dateien |
    Where-Object { $_.BaseName -match '^\s*\d+' } |
    Sort-Object {
        [int]([regex]::Match($_.BaseName, '^\s*\d+').Value)
    })

if ($Dateien.Count -eq 0) {
    Write-Host "Keine Dateien mit Tracknummer gefunden!"
    return
}

# ZUSÄTZLICHE METADATEN
$Zusatz = @()

if ($Jahr -ne "") {
    $Zusatz += @("-metadata", "date=$Jahr")
}

if ($Genre -ne "") {
    $Zusatz += @("-metadata", "genre=$Genre")
}

$MP3Dateien = @()
$Fehler = $false

# DATEIEN KONVERTIEREN
foreach ($Datei in $Dateien) {

    # DATEINAMEN BEREINIGEN
    $Name = $Datei.BaseName.Replace("(Audio)", "").Trim()

    # TRACKNUMMER UND TITEL LESEN
    if ($Name -match '^\s*(\d+)\s*-?\s*(.+)$') {
        $Track = $Matches[1]
        $Title = $Matches[2].Trim()
    }
    else {
        Write-Host "Kein Titel gefunden: $Name"
        $Fehler = $true
        continue
    }

    # DATEINAME MIT NUMMER UND BINDESTRICH
    $Name = "$Track - $Title"

    $Ausgabe = Join-Path $AlbumOrdner "$Name.mp3"

    # METADATEN SETZEN
    $Metadaten = @(
        "-metadata", "title=$Title",
        "-metadata", "track=$Track",
        "-metadata", "artist=$Artist",
        "-metadata", "album=$Album",
        "-metadata", "album_artist=$Artist"
    ) + $Zusatz

    # MP3 KONVERTIEREN
    if ($Datei.Extension.ToLower() -eq ".mp3") {
        $Codec = @("-c:a", "copy")
    }
    else {
        $Codec = @("-c:a", "libmp3lame", "-b:a", $Bitrate)
    }

    & ffmpeg -hide_banner -loglevel error -nostdin -y -i $Datei.FullName -map 0:a:0 -vn -map_metadata -1 @Codec @Metadaten -id3v2_version 3 $Ausgabe

    if ($LASTEXITCODE -eq 0 -and (Test-Path $Ausgabe)) {
        $MP3Dateien += $Ausgabe
        Write-Host "Fertig: $Name.mp3 (Track $Track)"
    }
    else {
        Write-Host "Fehler: $($Datei.Name)"
        $Fehler = $true
    }
}

# ALLE LIEDER ZUSAMMENFÜGEN
if ($MP3Dateien.Count -gt 0 -and -not $Fehler) {

    $Eingaben = @()
    $Filter = ""
    $Verbindung = ""

    for ($i = 0; $i -lt $MP3Dateien.Count; $i++) {

        $Eingaben += @("-i", $MP3Dateien[$i])

        $Filter += "[$($i):a:0]aresample=44100,aformat=channel_layouts=stereo,asetpts=PTS-STARTPTS[a$i];"

        $Verbindung += "[a$i]"
    }

    $Filter += "${Verbindung}concat=n=$($MP3Dateien.Count):v=0:a=1[out]"

    & ffmpeg -hide_banner -loglevel error -nostdin -y @Eingaben -filter_complex $Filter -map "[out]" -c:a libmp3lame -b:a $Bitrate -metadata "title=$Album" -metadata "album=$Album" -metadata "artist=$Artist" -metadata "album_artist=$Artist" @Zusatz $GesamtDatei

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Gesamtes Album erstellt: $GesamtDatei"
    }
    else {
        Write-Host "Fehler beim Zusammenfügen!"
    }
}

Write-Host "Fertig!"
