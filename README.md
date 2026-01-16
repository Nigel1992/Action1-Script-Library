[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Nigel1992)

> **Support this project* All donations go towards your chosen charity. You can pick any charity you'd like, and 5% is retained for Ko-Fi development costs. As a thank you, your name will be listed as a supporter/donor in this project. Feel free to email me at thedjskywalker@gmail.com for proof! :)

# Action1 RMM Script Library

This repository contains a collection of custom scripts designed for use with [Action1 RMM](https://www.action1.com), a cloud-based remote monitoring and management platform. These scripts help automate common IT administration, maintenance, security, and monitoring tasks.

## 📁 Repository Structure

Scripts are organized in a two-level folder structure:

- **By Functionality Category**
  - `maintenance/`
  - `software/`
  - `network/`
  - `security/`
  - `inventory/`
  - `utilities/`

- **By Script Language**
  - `powershell/` – Scripts written in PowerShell (`.ps1`)
  - `cmd/` – Windows Command Line (`.bat`, `.cmd`)
  - `vbs/` – Visual Basic Scripts (`.vbs`)
  - `bash/` – Linux/macOS scripts (`.sh`) for cross-platform use (where applicable)

### Example:
maintenance/
├── powershell/
│ └── ClearTempFiles.ps1
├── cmd/
│ └── DiskCleanup.cmd

software/
├── powershell/
│ └── InstallChrome.ps1


## ✅ How to Use with Action1

1. **Log in** to your [Action1 Dashboard](https://app.action1.com).
2. Navigate to **Configuration** → **Script Library**.
3. Click **"New Script"** and paste a script from this repo.
4. Assign to the relevant endpoints or groups.
5. Monitor the results in real-time through the dashboard.

Each script includes:

- 📄 A clear description of its purpose  
- 💻 Supported operating systems  
- 🔒 Required permissions (if any)  
- 🚦 Exit codes and output behavior  

## 🔐 Security Notice

Always review scripts before deploying them to production. Some scripts require administrative privileges and may modify system settings or files.

## 📌 Contributing

Want to share your scripts?

- Organize your script into the correct category and language subfolder  
- Include comments and a usage description at the top of the file  
- Follow naming conventions and best practices (PowerShell v5+ recommended)  
- Submit a pull request!  

## 📃 License

This project is licensed under the [Apache-2.0 license](LICENSE).

---

Made with ❤️ by an IT Professional, for fellow IT Professionals.
