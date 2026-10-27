# ⚔️ nocny-killer ⚔️
ubijacz aplikacji z timerem i anty-sleepem dla windowsa

<p align="center">
  <img width="600" alt="UCMX4UJ7Vmo" src="https://github.com/user-attachments/assets/315904ba-4675-402b-abd6-fc695e36d270" />
</p>


---

## 🚀 Główne funkcje

* **Automatyczne zamykanie wskazanych aplikacji po określonym czasie (`Timer`)**
* **Natychmiastowe ubijanie procesów (`KILL!Now`)**
* **Zapobieganie usypianiu systemu**
* **Wizualny pasek postępu i bieżące logi (error log z opcją do pliku)**

---

## 🛠️ Wymagania

* System operacyjny **Windows** (PowerShell 5.1 lub nowszy).
* Brak dodatkowych instalacji – skrypt korzysta z natywnych bibliotek .NET (`System.Windows.Forms`, `System.Drawing`).

---

## 📦 Uruchomienie

1. Pobierz lub sklonuj repozytorium.
2. Kliknij prawym przyciskiem myszy na plik skryptu `.ps1` i wybierz **Uruchom za pomocą programu PowerShell**.
3. Dodaje też .vbs - który po edycji pozwoli na uruchomienie po dwukliku lub dodanie go do np. autostartu czy context menu

---

## ⚙️ Konfiguracja aplikacji

Listę kontrolowanych procesów, czasy odliczania oraz domyślny stan przełączników można łatwo dostosować bezpośrednio w kodzie skryptu PowerShell (`ps_3.ps1`) w sekcji **0) KONFIGURACJA**:

```powershell
$script:Config = [ordered]@{
    preventSleepEnabled = $true
    writeErrorLog       = $false
    apps = @(
        [pscustomobject]@{ name = "firefox"; minutes = 60; enabled = 1; killNow = 0 }
        [pscustomobject]@{ name = "msedge"; minutes = 60; enabled = 1; killNow = 0 }
        [pscustomobject]@{ name = "vivaldi"; minutes = 60; enabled = 1; killNow = 0 }
        [pscustomobject]@{ name = "SamsungFlowDesktop"; minutes = 60; enabled = 1; killNow = 0 }
        [pscustomobject]@{ name = "paint shop pro"; minutes = 60; enabled = 1; killNow = 1 }
        # Możesz dodawać własne procesy, podając:
        # - name: dokładną nazwę procesu (bez .exe)
        # - minutes: czas odliczania w minutach
        # - enabled: domyślny stan timera (1 = włączony, 0 = wyłączony)
        # - killNow: domyślny stan dla natychmiastowego zamknięcia (1 = zaznaczony)
    )
    # ...
}
```

---

## 📄 Licencja

Ten projekt jest objęty licencją **MIT** – zobacz plik [LICENSE](LICENSE) po więcej szczegółów.
