# Linux Setup Script

This script automates the setup of a Linux environment on Ubuntu, Fedora, and Nobara distributions. It installs essential applications, themes, fonts, custom shortcuts, and configures various settings.

## Prerequisites

- A fresh install of Ubuntu, Fedora, or Nobara.
- An active internet connection.

## Installation and Usage

1.  **Clone the Repository:**

    ```bash
    git clone https://github.com/AbuTaha7000D/linux-postinstall.git
    cd linux-postinstall
    ```

2.  **Run the Script:**

    ```bash
    ./setup.sh [option]
    ```

    - **Available Options:**

      - `all`: Runs all install functions, including adding `google dns`, installing `fonts`, `themes`, `language`, `atuin`, `apps`, `flatpaks`, `aliases`, `shortcuts`, `favorite` apps.
      - `apps`: Installs the system applications, including `vscode`, `brave`, `chrome`, and more, and also installs `flatpaks` and `atuin`.
      - `flatpaks`: Installs only flatpak applications, including `discord`, `spotify`, `bitwarden`and more.
      - `atuin`: Installs only Atuin, a shell history sync tool, asking the user for their credentials.
      - `dns`: Adds Google's public DNS servers.
      - `fonts`: Installs custom fonts.
      - `themes`: Installs custom themes, prompting the user to choose from a list.
      - `lang`: Changes the system language to English.
      - `aliases`: Sets up custom aliases in the `~/.bashrc` file.
      - `shortcuts`: Sets up custom keyboard shortcuts.

    - **Examples:**
      - To run all steps: `./setup.sh all`
      - To install only fonts: `./setup.sh fonts`
      - To install apps and add Google's public DNS servers: `./setup.sh apps dns`

3.  **Theme Selection:**
    - When the script runs for the first time, or if you call `./setup.sh themes`, it will display a list of available themes and ask you to choose one or choose a default.
4.  **Atuin Integration:**
    - When the script runs for the first time, or if you call `./setup.sh atuin`, it will display a prompt for your Atuin credentials. You can skip this step by pressing enter.

## Known Issues

- If there is a problem downloading an app or adding a repository then the app/repository won't be installed but the script won't fail and will continue the installation.

## Attributions

This project includes the following fonts and themes:

### Fonts

- **Cairo Family:** ([https://fonts.google.com/specimen/Cairo](https://fonts.google.com/specimen/Cairo))

- **NerdFont Family:** ([https://github.com/ryanoasis/nerd-fonts](https://github.com/ryanoasis/nerd-fonts))

- **Montserrat Family:** ([https://fonts.google.com/specimen/Montserrat](https://fonts.google.com/specimen/Montserrat))

- **Mudir MT:** ([https://fontsgeek.com/fonts/Mudir-MT-Regular](https://fontsgeek.com/fonts/Mudir-MT-Regular))

- **OpenSauceSans:** ([https://github.com/marcologous/Open-Sauce-Fonts](https://github.com/marcologous/Open-Sauce-Fonts))

- **Ubuntu Font Family** ([https://design.ubuntu.com/font](https://design.ubuntu.com/font))

### Themes

- **Graphite Multicolor Mode:** ([https://www.gnome-look.org/p/2014493/](https://www.gnome-look.org/p/2014493/))
  - Created by vinceliuice ([https://github.com/vinceliuice/Graphite-gtk-theme](https://github.com/vinceliuice/Graphite-gtk-theme))

## Contributing

Feel free to submit a pull request, report a bug, or suggest improvements to this script.
