#!/usr/bin/env bash
# Build a release of the app that can actually reach production.
#
#   BACKEND_URL=https://api.example.com ./build_release.sh apk          # sideload
#   BACKEND_URL=https://api.example.com ./build_release.sh appbundle    # Play Store
#   BACKEND_URL=https://api.example.com ./build_release.sh ipa          # App Store / TestFlight
#
# It refuses the two mistakes that produce an app which installs fine and then
# cannot do anything:
#   - no BACKEND_URL, or a plain-http one. The default is a laptop address, and
#     release builds only allow HTTPS (network_security_config.xml, iOS ATS).
#   - an Android build signed with the debug key. Play rejects it, and users who
#     sideload it cannot upgrade to a properly signed build without uninstalling.
#     Set ALLOW_DEBUG_SIGNING=1 only for a throwaway internal APK.
#
# BUILD_NAME / BUILD_NUMBER override pubspec's version (e.g. 1.0.0 / 2).
# Premium: REVENUECAT_APPLE_KEY, REVENUECAT_GOOGLE_KEY, TERMS_URL, PRIVACY_URL
# (see DEPLOY.md). Leave them out and the build has no upgrade prompts at all.

set -euo pipefail
cd "$(dirname "$0")"

target="${1:-apk}"
case "$target" in apk|appbundle|ipa) ;; *)
  echo "usage: BACKEND_URL=https://… $0 [apk|appbundle|ipa]" >&2; exit 2 ;;
esac

url="${BACKEND_URL:-}"
url="${url%/}"
if [[ -z "$url" ]]; then
  echo "✗ BACKEND_URL is not set. Point it at the production API, e.g." >&2
  echo "    BACKEND_URL=https://api.example.com $0 $target" >&2
  exit 1
fi
if [[ "$url" != https://* ]]; then
  echo "✗ BACKEND_URL must be https:// — release builds refuse plain HTTP: $url" >&2
  exit 1
fi

if [[ "$target" != ipa && ! -f android/key.properties && "${ALLOW_DEBUG_SIGNING:-}" != 1 ]]; then
  cat >&2 <<'EOF'
✗ android/key.properties is missing, so this would be signed with the debug key.
  Create an upload key once, keep it (and its passwords) somewhere safe forever:

    keytool -genkey -v -keystore ~/backpac-upload.jks -keyalg RSA -keysize 2048 \
            -validity 10000 -alias upload

  then write android/key.properties (git-ignored):

    storeFile=/Users/<you>/backpac-upload.jks
    storePassword=…
    keyAlias=upload
    keyPassword=…

  Or ALLOW_DEBUG_SIGNING=1 for a throwaway internal APK.
EOF
  exit 1
fi

# Before anything slow, prove the URL is the API and it is up.
if ! curl -sf --max-time 10 "$url/healthz" >/dev/null; then
  echo "✗ $url/healthz did not answer. Is the backend deployed?" >&2
  exit 1
fi

defines=(
  "--dart-define=BACKEND_URL=$url"
  "--dart-define=LIVE_VOICE=true"
)
[[ -n "${SUPABASE_URL:-}" ]] && defines+=("--dart-define=SUPABASE_URL=$SUPABASE_URL")
[[ -n "${SUPABASE_PUBLISHABLE_KEY:-}" ]] && defines+=("--dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY")
[[ -n "${AGENT_ID:-}" ]] && defines+=("--dart-define=AGENT_ID=$AGENT_ID")

# Premium. All optional: without them the build ships with every upgrade
# prompt hidden. The keys are RevenueCat's *public* SDK keys (safe in an app);
# the App Store requires the two links on any screen selling a subscription,
# so the upgrade screen stays hidden until both are set.
for v in REVENUECAT_APPLE_KEY REVENUECAT_GOOGLE_KEY TERMS_URL PRIVACY_URL PREMIUM_ENTITLEMENT; do
  if [[ -n "${!v:-}" ]]; then defines+=("--dart-define=$v=${!v}"); fi
done
if [[ -z "${TERMS_URL:-}" || -z "${PRIVACY_URL:-}" ]]; then
  echo "• no TERMS_URL / PRIVACY_URL: Premium stays hidden in this build"
fi

version=()
[[ -n "${BUILD_NAME:-}" ]] && version+=("--build-name=$BUILD_NAME")
[[ -n "${BUILD_NUMBER:-}" ]] && version+=("--build-number=$BUILD_NUMBER")

echo "• building $target against $url"
flutter pub get
flutter build "$target" --release "${defines[@]}" "${version[@]}"

echo
echo "✓ built. Backend compiled in: $url"
