## What this changes

<!-- One or two sentences. If it fixes an issue, "Fixes #123". -->

## How you tested it

<!-- "Builds clean" is not testing. Say what you actually saw in the menu bar. For anything visual,
     attach a screenshot of the menu bar title and the open dropdown. -->

## Checklist

- [ ] `./build.sh` succeeds and the app runs
- [ ] No new dependencies (AppKit, Foundation, UserNotifications, ServiceManagement only)
- [ ] Nothing logs, prints, or commits the OAuth token or credentials file contents
- [ ] New parsing of the usage endpoint degrades to `–` instead of crashing when a field is
      missing, null, or the wrong type
- [ ] One change per PR
