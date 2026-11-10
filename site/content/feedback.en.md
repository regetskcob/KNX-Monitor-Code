---
title: "Feedback"
description: "Report bugs and ask about your installation without uploading your ETS project: with the diagnostics package from Busclear."
layout: "page"
slug: "feedback"
---
For bugs and questions about your installation we often need your group addresses and details from the ETS project. Please do not upload your project for that and do not send us a password: a `.knxproj` file holds more than we need, and forums and GitHub issues are public. That is what the **diagnostics package** is for.

## The diagnostics package

A ZIP file that Busclear puts together for you. Before sending you see exactly what is in it ("View file contents").

**Included:** the bus recording around the fault; from the project the group addresses, datapoint types, devices and links; your description, your comments, the app's recent messages and technical facts: app and add-on version, platform, operating system or browser, connection mode, type and name of the gateway.

**Not included:** the ETS project file and its password, keyring and keys, and passwords. Data Secure telegrams are in it only with time and addresses, without content.

**Filtered where recognisable:** IP addresses, host names, MAC and serial numbers, e-mail addresses and known names of project, installation and customer; project and installation names are replaced by placeholders. **This is not a guarantee:** the filter does not recognise names you type or that appear in group addresses, and telegram values can show when someone is at home. So take a quick look through the package before sending it.

**Screenshots** are only included if you turn that on; it is off by default. They are not filtered, everything visible on them reaches us.

**Names:** whether the names of your group addresses and devices go along is up to you, with the switch "Include names". They help us a lot; without them there are only addresses and products.

{{< diag-names >}}

**Fault report to your electrician:** this is different from the diagnostics package for us. It includes names and the screenshots on your comments, without a switch. So only attach what the recipient may see.

## How to create it

1. Open Busclear (app or Home Assistant add-on), connect to the bus, with the ETS project loaded.
2. **Does the fault still happen?** Under Tools › Report a problem start recording, reproduce the fault and tap "It happened now" each time. The package then covers everything from the start.
3. **Otherwise** under Tools › Diagnostics package describe what happened, pick the time around the fault and decide whether names go along.
4. "Share package", "Save package" or in the browser "Download package".

## Where to send it

**By e-mail to [support@busclear.de](mailto:support@busclear.de)**, with a sentence or two about the problem. The package stays with us and is not published.

If you write in a forum or in a [GitHub issue](https://github.com/regetskcob/KNX-Monitor/issues), a note "sent a diagnostics package by e-mail" is enough there. Please do not attach the package there: both are public.

**After a crash** Busclear shows a notice at the next start that leads to the diagnostics package. There, "Report as issue" opens a prefilled form on GitHub with only version, platform, time and kind of crash. On the Busclear Box, tap the line with the unexpected restarts to see the recent restarts with their reason.

We open the package in Busclear, reproduce the fault and use it only for that. Once your request is done, we delete it. More in the [privacy policy](/en/privacy/).

## Not using Busclear yet?

If it is only about the import, for example because your project does not load, the group address export as CSV from ETS (Group addresses › Export) often helps us already. It contains no password.

## Ideas and wishes

We collect new features in public in the [GitHub issues](https://github.com/regetskcob/KNX-Monitor/issues). Vote with 👍 for what you need there, or open a new issue.
