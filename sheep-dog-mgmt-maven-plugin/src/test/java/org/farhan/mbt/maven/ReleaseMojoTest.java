package org.farhan.mbt.maven;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

class ReleaseMojoTest {

	private final ReleaseMojo mojo = new ReleaseMojo();

	// The #495 fix: a pinned X-SNAPSHOT becoming its own release X must count
	// as a dependency change, otherwise a dependency-only fix never triggers a
	// downstream re-release.
	@Test
	void snapshotBecomingItsOwnReleaseIsAnUpgrade() {
		assertTrue(mojo.isUpgrade("1.5-SNAPSHOT", "1.5"));
	}

	// A genuine version bump is still an upgrade (X-SNAPSHOT -> Y>X).
	@Test
	void higherReleaseIsAnUpgrade() {
		assertTrue(mojo.isUpgrade("1.5-SNAPSHOT", "1.6"));
		assertTrue(mojo.isUpgrade("1.4", "1.5"));
	}

	// allowDowngrade resolving a SNAPSHOT-ahead-of-release down to the latest
	// release (X-SNAPSHOT -> W<X) is NOT a change. Guards #240.
	@Test
	void downgradeIsNotAnUpgrade() {
		assertFalse(mojo.isUpgrade("1.5-SNAPSHOT", "1.4"));
		assertFalse(mojo.isUpgrade("1.10-SNAPSHOT", "1.9"));
	}

	// Same release on both sides is not a change.
	@Test
	void sameReleaseIsNotAnUpgrade() {
		assertFalse(mojo.isUpgrade("1.5", "1.5"));
	}

	// The post-release re-bump must not self-perpetuate: a release going back
	// to its own SNAPSHOT (X -> X-SNAPSHOT) and a SNAPSHOT staying a SNAPSHOT
	// (X-SNAPSHOT -> X-SNAPSHOT, no upstream release yet) are both non-upgrades.
	// Guards #338.
	@Test
	void releaseBackToSnapshotIsNotAnUpgrade() {
		assertFalse(mojo.isUpgrade("1.5", "1.5-SNAPSHOT"));
		assertFalse(mojo.isUpgrade("1.5-SNAPSHOT", "1.5-SNAPSHOT"));
	}
}
