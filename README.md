# Holyshit

A World of Warcraft (Classic) addon with personal healing quality-of-life customizations. New features are added over time.

## Features

While you are in a party inside a dungeon (not in raids or the open world):

- **Under attack call-out**: when you take damage, yells "Help! I'm getting attacked!". Only damage triggers it (not pulling aggro), and it is silenced for 1 minute so repeated attacks do not spam.
- **Out of mana warning**: when your mana drops below what your Heal spell costs (highest known rank), says "I'm out of mana." in party chat. Silenced for 1 minute.

- **Damage per second on unit frames**: shows how much damage per second you and each party member are taking (averaged over the last 8 seconds) above the frame, so you can judge which heal to use. The color shows how long until the current health would be drained at that rate: red within 5 seconds, yellow within 10, green within 15, white beyond that. Works with the default Blizzard party frames and the raid-style party/raid frames (shown bottom right in the frame); shown while grouped. Toggle with `/holyshit dtps` (saved between sessions).

## Usage

- `/holyshit` shows the status and the cooldown settings.
- `/holyshit dtps` toggles the damage per second display.

## Installation

Copy this folder to `World of Warcraft/_classic_/Interface/AddOns/Holyshit` (the folder name must be `Holyshit`).
