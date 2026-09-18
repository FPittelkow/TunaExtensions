# 2Do Extension

Open the Today Focus List of [2Do](https://www.2doapp.com) from Tuna.

## What it does

- Adds a **2Do Today** item to the `twodo` catalog.
- **Show in 2Do** opens the Today Focus List with the documented
  `twodo://x-callback-url/showtoday` URL.
- **Add to 2Do Inbox** creates a task in the Inbox from the text you have typed into Tuna, using
  `twodo://x-callback-url/add?task=…&forlist=Inbox`.
- **Add to 2Do Today** does the same but marks the task due today with
  `twodo://x-callback-url/add?task=…&forlist=Inbox&due=0`.

This first version is deliberately narrow: it exposes one stable item and three target-free actions.
It does not search or index your tasks, and it does not read anything from 2Do.

## Setup

1. Install 2Do for Mac from the Mac App Store.
2. Make sure the `2Do` source is enabled under Tuna's extensions.

No account, token, or API key is required. The extension only opens the app's URL scheme.

## Permissions

None. Tuna does not request any system permissions for this extension.

## Privacy

The extension makes no network requests and reads no personal data. It only constructs the fixed
`twodo://` URL and asks macOS to open it. Nothing about your tasks leaves the app.

## Quotas

None. The extension does not call any rate-limited or paid service.

## Writes

The extension never writes files or calls an API. **Add to 2Do Inbox** and **Add to 2Do Today** hand
a `twodo://` URL to macOS, and 2Do itself creates the task in the Inbox. No task title is stored by
the extension.

## Limitations

- Only the Today Focus List is exposed. Other lists and searches are not yet available.
- The add actions only set the task title (and, for **Add to 2Do Today**, a due date of today); notes,
  due times, tags, and priorities are not yet exposed, and the task always lands in the Inbox.
- 2Do for Mac must be installed, otherwise **Show in 2Do** reports a failure and suggests installing
  it.
- The item is static and does not refresh; it always points at the same URL.
