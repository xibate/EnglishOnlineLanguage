# English Online Language

A World of Warcraft: **WoW Forever** addon that keeps **Preferred Online Language**
(Options → System → Languages and Social) set to **English**.

On some EU accounts this account-wide setting keeps getting set to French (or another
language). This addon checks it when you log in and when you open the Options window.
If it isn't English, the addon switches it to English and applies the change.

## Installation

1. Download this repository (Code → Download ZIP) and extract it.
2. Put the `EnglishOnlineLanguage` folder in
   `World of Warcraft\_forever_\Interface\AddOns\`.
   The folder must contain `EnglishOnlineLanguage.toc` directly. If you downloaded the
   ZIP, rename `EnglishOnlineLanguage-main` to `EnglishOnlineLanguage`.
3. Restart the game, or type `/reload`.

## Commands

| Command | What it does |
| --- | --- |
| `/eol` | Set the language to English now |
| `/eol scan` | Print the setting, its options and related APIs/CVars |
| `/eol off` / `/eol on` | Turn automatic fixing off or on |

## Notes

- Blizzard puts a **24-hour cooldown** on changing this setting. If the setting was
  changed recently, the change may be refused. The addon then shows a chat message.
- The addon finds the setting through Blizzard's Settings panel
  (`PROXY_PREFERRED_PLAY_LOCALE`, English = `9`). It doesn't rely on a hard-coded API.
- A short log is stored in `WTF\Account\<account>\SavedVariables\EnglishOnlineLanguage.lua`.
  The game writes this file when you log out or `/reload`.
