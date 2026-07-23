const BUS_NEARBY_TOKEN_KEY = "transit-nearby.busnearby-token.v1"

export function getBusNearbyToken(): string | null {
  const value = Keychain.get(BUS_NEARBY_TOKEN_KEY)
  return value?.trim() || null
}

export function hasBusNearbyToken(): boolean {
  return getBusNearbyToken() != null
}

export function setBusNearbyToken(value: string): boolean {
  const token = value.trim().replace(/^Bearer\s+/i, "")
  if (!token) return false
  return Keychain.set(BUS_NEARBY_TOKEN_KEY, token, {
    accessibility: "unlocked_this_device",
    synchronizable: false,
  })
}

export function removeBusNearbyToken(): boolean {
  return Keychain.remove(BUS_NEARBY_TOKEN_KEY)
}

export function busNearbyAuthorizationHeader(): Record<string, string> {
  const token = getBusNearbyToken()
  return token ? { Authorization: `Bearer ${token}` } : {}
}
