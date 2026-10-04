# Hitesh's GitHub profile and discovery plan

## What the audit found

On October 4, 2026, the public GitHub API showed 27 public repositories, the bio “I like building tech.”, an empty website field, and no accessible `Hiteshldt/Hiteshldt` profile repository. You already pin three IoT projects: `cb-algal-lab-culture-monitoring`, `cb-lab-co2-flow-monitoring`, and `cb-pbr-configurator`. Most public projects have no description. SoundSwipe already has a detailed description, relevant topics, screenshots, a license, CI, and preview releases. Build on that foundation.

FineTune's page in the reference is a **repository page**, not its developer's personal profile. Its README, release downloads, documentation, funding links, and community activity make the project easy to evaluate. Profile setup helps visitors understand who built it; neither setup nor keywords guarantee stars or search placement.

## Set up your profile

1. Open [profile settings](https://github.com/settings/profile). Use a recognizable photo and the name **Hitesh Gupta**. Suggested bio: **Building practical tools for macOS, the web, and connected devices. Creator of SoundSwipe — free per-app audio control for Mac.**
2. Add `https://ayuvam.com` as your website if it is the destination you want visitors to use. Add X and Ko-fi to your social links. Add a public contact email only if you want it visible.
3. Create a **public** repository named exactly **Hiteshldt** and put [this prepared README](profile/README.md) in its root as `README.md`. GitHub shows a nonempty root README from a public repository matching your username on your profile. [Official instructions](https://docs.github.com/en/account-and-profile/how-tos/profile-customization/managing-your-profile-readme).
4. On your profile, choose **Customize your pins**. Add SoundSwipe as your first pin, then keep two or three projects that are working, documented, and safe to share. Candidates from your public list include `diagnostic-booking-api`, `cb-iot-automation-test-tool`, and `personal_finance_tracker`; review their code and setup before featuring them. Public metadata alone does not establish their quality. [Profile customization](https://docs.github.com/en/account-and-profile/how-tos/profile-customization).
5. Give each selected project a one-sentence description, screenshot or example request, setup steps, license, and link to a working demo where available. Archive genuinely abandoned work only after reviewing it; don't delete repositories just to make the profile look tidy.

The profile README is a draft here; pushing SoundSwipe does not create the separate profile repository or change account settings.

## Make SoundSwipe easier to evaluate

- Keep the download link, real screenshots, supported macOS versions, permission steps, and preview limitations near the top of the README.
- The new `.github/FUNDING.yml` points to `ko_fi: hiteshgupta`. If the Sponsor button is hidden, enable **Settings → General → Features → Sponsorships**. This links Ko-fi; it does not enroll you in GitHub Sponsors. [Funding documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/displaying-a-sponsor-button-in-your-repository).
- Upload `docs/images/social-preview.png` under **Settings → General → Social preview**. Keep its text aligned with the actual app. [Social preview documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview).
- Keep your existing specific topics such as `macos`, `per-app-volume`, `coreaudio`, `swiftui`, and `audio-routing`. Topics help people find related projects; adding unrelated popular terms will not build useful interest. [Topics documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics).
- Prioritize signed, notarized downloads and reliable hardware behavior. The current unsigned preview installation adds friction. Do not advertise Homebrew installation until a real cask exists.

## A practical four-week plan

| When | Deliverable |
| --- | --- |
| Week 1 | Profile README, bio, website, three strong pins, and a 20–30 second demo showing separate music/call volumes. |
| Week 2 | Ask a small group of Mac users to test on built-in, USB, HDMI, and Bluetooth devices. Track reproducible issues with OS/device details. |
| Week 3 | Publish a preview with clear release notes and a short technical post about a real problem solved in the project. Share in relevant communities that allow project posts; disclose that you built it. |
| Week 4 | Fix the most common onboarding or audio issue, improve the docs from feedback, and repeat with a new demo. |

Measure downloads, returning testers, resolved bugs, and helpful contributions. Stars are a possible result of useful software and sustained visibility, not a setting to enable. Avoid mass promotion, bought stars, and decorative contribution widgets that distract from working projects.
