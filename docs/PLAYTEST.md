# Playing glaze together

Two players, one hosts and one joins. The host plays Ari and Bram, the guest
Cel and Dov. Playing alone, you control all four.

## 1. Get connected (pick one)

**Tailscale (easiest, works anywhere)**

1. Both install Tailscale (tailscale.com) and sign in, and the host invites
   the guest to their tailnet (or both use the same account).
2. The host's Tailscale address starts with `100.` — the game shows it on the
   main menu and in the top-left corner while hosting.

**Same home network**

Use the host's local address (often `192.168.x.x`), also shown in the game.

**Over the internet without Tailscale**

The host forwards **UDP port 24560** on their router to their PC, and gives
the guest their public IP address. Windows Firewall may ask to allow glaze the
first time you host: allow it.

## 2. Start a session

1. The host starts `glaze.exe`, picks a level (Arena is a good first fight)
   and clicks **Host co-op**.
2. The guest starts `glaze.exe`, types the host's address in the box and
   clicks **Join**. Joining mid-fight is fine.

## 3. Playing

- On the party's turn you both act at the same time with your own
  characters. The turn ends once **both** of you press **End turn** (it lights
  up when your characters are out of moves).
- You can click your partner's characters to look at them, not control them.
- Knocking an enemy down takes hits landing within one round — coordinate.
- **F10** leaves the session. If the guest leaves, the host takes over their
  characters; the guest can rejoin any time and picks up where things are.
- The top-left corner shows the connection and the ping.

## If something goes wrong

- *"Couldn't reach the host"*: check the address, that the host clicked Host
  co-op, and (without Tailscale) the port forwarding and firewall.
- Out-of-sync games fix themselves: the guest quietly reloads the host's
  state. If it keeps happening, tell Daniel.
