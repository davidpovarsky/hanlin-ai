// Prefer stable packages compatible with the embedded engine, not merely the
// registry's newest release. Type declarations must also stay at/below its API line.
export function selectHostPackageVersion(name, metadata, nodeVersion, satisfiesNode = () => true) {
  const latest = metadata['dist-tags']?.latest;
  const compatible = version => {
    const requirement = metadata.versions?.[version]?.engines?.node;
    return !requirement || satisfiesNode(nodeVersion, requirement);
  };
  const compare = (a, b) => {
    const left = a.split('.').map(Number), right = b.split('.').map(Number);
    return left[0] - right[0] || left[1] - right[1] || left[2] - right[2];
  };
  let versions = Object.keys(metadata.versions ?? {}).filter(version => /^\d+\.\d+\.\d+$/.test(version) && compatible(version));
  let version = latest;
  if (name === '@types/node') {
    const [major, minor] = nodeVersion.split('.').map(Number);
    versions = versions.filter(candidate => {
      const [candidateMajor, candidateMinor] = candidate.split('.').map(Number);
      return candidateMajor === major && candidateMinor <= minor;
    });
    version = versions.sort(compare).at(-1);
  } else if (latest && metadata.versions?.[latest] && !compatible(latest)) {
    version = versions.filter(candidate => compare(candidate, latest) < 0).sort(compare).at(-1);
  }
  if (!version || !metadata.versions?.[version] || !compatible(version)) throw new Error(`npm has no compatible exact version for ${name} on Node ${nodeVersion}.`);
  return version;
}
