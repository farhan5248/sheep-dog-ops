package org.farhan.mbt.maven;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

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

	// The #500 fix: the umbrella chart pom reuses the .version property names as
	// tags inside the release plugin's <imageTagMap> config, after <properties>.
	// extractVersionProperties must read the real versions from <properties>, not
	// the chart-key values from imageTagMap (which would shadow them via last-wins
	// put and make every dependency-only release skip).
	@Test
	void extractVersionPropertiesIgnoresImageTagMapCollision(@TempDir File dir) throws Exception {
		File pom = new File(dir, "pom.xml");
		Files.write(pom.toPath(), ("<project>\n"
				+ "  <properties>\n"
				+ "    <sheep-dog-graphml-api-svc.version>1.5</sheep-dog-graphml-api-svc.version>\n"
				+ "    <sheep-dog-mcp-svc.version>1.31</sheep-dog-mcp-svc.version>\n"
				+ "  </properties>\n"
				+ "  <build><plugins><plugin><configuration>\n"
				+ "    <imageTagMap>\n"
				+ "      <sheep-dog-graphml-api-svc.version>graphmlApi</sheep-dog-graphml-api-svc.version>\n"
				+ "      <sheep-dog-mcp-svc.version>mcp</sheep-dog-mcp-svc.version>\n"
				+ "    </imageTagMap>\n"
				+ "  </configuration></plugin></plugins></build>\n"
				+ "</project>\n").getBytes(StandardCharsets.UTF_8));

		Map<String, String> versions = mojo.extractVersionProperties(pom);

		assertEquals("1.5", versions.get("sheep-dog-graphml-api-svc.version"));
		assertEquals("1.31", versions.get("sheep-dog-mcp-svc.version"));
	}
}
