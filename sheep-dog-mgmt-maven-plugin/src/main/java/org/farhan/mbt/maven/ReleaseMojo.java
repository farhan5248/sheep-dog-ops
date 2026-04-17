package org.farhan.mbt.maven;

import java.io.File;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugin.MojoFailureException;
import org.apache.maven.plugins.annotations.Mojo;
import org.apache.maven.plugins.annotations.Parameter;
import org.apache.maven.project.MavenProject;

// aggregator=true so multi-module reactor builds only run this once on the root,
// not on each child module
@Mojo(name = "release", aggregator = true)
public class ReleaseMojo extends AbstractMojo {

	@Parameter(defaultValue = "${project}", readonly = true)
	public MavenProject project;

	@Parameter(property = "preparationGoals", defaultValue = "deploy,-DskipTests")
	public String preparationGoals;

	// Optional: when set, the release flow also rewrites image tags in a
	// values.yaml file after updating the version files. Used by the
	// sheep-dog umbrella chart pom to publish versioned image references
	// alongside the chart release. Each map entry is
	// <pom-property-name> -> <values.yaml-service-block-key>, e.g.
	// asciidoc-api-svc.version -> asciidocApi. The pom property must
	// already be resolved to a concrete version (versions-maven-plugin
	// runs before this mojo), and the values.yaml must have a matching
	// block under `images:` with a `tag:` line to rewrite.
	@Parameter
	public Map<String, String> imageTagMap;

	// Path to values.yaml relative to the project basedir. Only used when
	// imageTagMap is non-empty. Default assumes the sheep-dog umbrella
	// chart layout; other chart projects (e.g. future tamarian) can
	// override via plugin configuration.
	@Parameter(property = "valuesYamlPath", defaultValue = "helm/sheep-dog/values.yaml")
	public String valuesYamlPath;

	@Override
	public void execute() throws MojoExecutionException, MojoFailureException {
		String workingDir = project.getBasedir().getAbsolutePath();
		GitRunner git = new GitRunner(getLog());
		MavenRunner mvn = new MavenRunner(getLog());

		try {
			// Start from a known clean state matching remote, so local experiments
			// or failed builds don't interfere
			runOrFail(git, workingDir, "reset", "--hard", "HEAD");
			runOrFail(git, workingDir, "clean", "-fdx");
			runOrFail(git, workingDir, "pull");

			// Resolve SNAPSHOT dependency properties to release versions so the
			// released artifact depends on stable releases, not moving targets.
			// -DallowDowngrade=true is required because in a multi-repo ecosystem
			// deps release independently and this pom's SNAPSHOTs are commonly
			// AHEAD of the latest releases in Nexus (e.g. pom has 1.10-SNAPSHOT,
			// Nexus latest release is 1.9). Without allowDowngrade, maven's
			// update-properties leaves the SNAPSHOT in place because the existing
			// version is "newer" from a semver standpoint, and the released
			// artifact ends up depending on a SNAPSHOT. With allowDowngrade, it
			// picks the latest available release regardless — which is what
			// "release" means: pin to stable, immutable, shippable today. See #239.
			File pomFile = new File(project.getBasedir(), "pom.xml");
			Map<String, String> versionsBefore = extractVersionProperties(pomFile);
			runOrFail(mvn, workingDir,
					"org.codehaus.mojo:versions-maven-plugin:update-properties",
					"-DallowSnapshots=false",
					"-DallowDowngrade=true");
			Map<String, String> versionsAfter = extractVersionProperties(pomFile);

			// A real dependency change is a version UPGRADE. allowDowngrade also
			// rewrites SNAPSHOT-ahead-of-release down to the latest release (e.g.
			// 1.10-SNAPSHOT -> 1.9) every run; if we counted that as a change
			// we'd cycle forever because the post-release SNAPSHOT bump puts it
			// back and the next run sees the same "change" again. See #240.
			boolean dependencyChange = hasUpgradedDependencies(versionsBefore, versionsAfter);
			boolean sourceChange = hasSourceChanges(git, workingDir);

			if (!dependencyChange && !sourceChange) {
				getLog().info("No dependency changes and no source changes since last release, skipping");
				// update-properties may have rewritten pom.xml (allowDowngrade
				// resolves SNAPSHOTs to older releases every run). Since we're
				// not releasing, revert so the working tree stays clean.
				runOrFail(git, workingDir, "reset", "--hard", "HEAD");
				return;
			}

			if (dependencyChange) {
				getLog().info("Dependency changes detected, releasing");
			}
			if (sourceChange) {
				getLog().info("Source changes since last release, releasing");
			}

			// Remove -SNAPSHOT suffix from version strings across all project files
			// (pom.xml, OSGi MANIFEST.MF, Eclipse feature.xml) to create the release version
			String cv = project.getVersion().replace("-SNAPSHOT", "");
			getLog().info("current version: " + cv);

			updateVersion(project.getBasedir(), "<version>", cv + "-SNAPSHOT</version>", cv + "</version>", "pom.xml");
			updateVersion(project.getBasedir(), "Bundle-Version: ", cv + ".qualifier", cv + "", "MANIFEST.MF");
			updateVersion(project.getBasedir(), "version=\"", cv + ".qualifier\"", cv + "\"", "feature.xml");
			updateVersion(project.getBasedir(), "\"version\": \"", cv + "-SNAPSHOT\"", cv + "\"", "package.json");
			// Helm chart version + appVersion. Two calls because the two
			// lines differ in quoting (version: is unquoted, appVersion: "..."
			// is quoted per Helm convention).
			updateVersion(project.getBasedir(), "version: ", cv + "-SNAPSHOT", cv, "Chart.yaml");
			updateVersion(project.getBasedir(), "appVersion: \"", cv + "-SNAPSHOT\"", cv + "\"", "Chart.yaml");

			// For chart projects: rewrite image tags in values.yaml from
			// resolved pom dependency versions. Mojo does nothing unless
			// the caller configured imageTagMap.
			if (imageTagMap != null && !imageTagMap.isEmpty()) {
				updateValuesYaml(project.getBasedir(),
						new File(project.getBasedir(), valuesYamlPath), imageTagMap);
			}

			gitCommit(git, workingDir, "[Release] Prepare release " + project.getArtifactId() + "-" + cv);
			gitTag(git, workingDir, project.getArtifactId() + "-" + cv);

			// Build and publish the release artifacts
			getLog().info("Run Maven deploy");
			mvnPhase(mvn, workingDir, preparationGoals);

			// Tycho/Eclipse projects need 3-part versions (OSGi requires major.minor.patch),
			// while regular Maven projects use 2-part
			String[] cvParts = cv.split("\\.");
			String nv;
			if (cvParts.length >= 3) {
				nv = cvParts[0] + "." + cvParts[1] + "." + String.valueOf(Integer.parseInt(cvParts[2]) + 1);
			} else {
				nv = cvParts[0] + "." + String.valueOf(Integer.parseInt(cvParts[1]) + 1);
			}
			getLog().info("next version: " + nv);

			// Set up for next development cycle
			updateVersion(project.getBasedir(), "<version>", cv + "</version>", nv + "-SNAPSHOT</version>", "pom.xml");
			updateVersion(project.getBasedir(), "Bundle-Version: ", cv + "", nv + ".qualifier", "MANIFEST.MF");
			updateVersion(project.getBasedir(), "version=\"", cv + "\"", nv + ".qualifier\"", "feature.xml");
			updateVersion(project.getBasedir(), "\"version\": \"", cv + "\"", nv + "-SNAPSHOT\"", "package.json");
			updateVersion(project.getBasedir(), "version: ", cv, nv + "-SNAPSHOT", "Chart.yaml");
			updateVersion(project.getBasedir(), "appVersion: \"", cv + "\"", nv + "-SNAPSHOT\"", "Chart.yaml");
			// values.yaml image tags are NOT reverted on the post-release
			// bump. They stay at whatever was resolved during this release
			// cycle. The next release run will overwrite them with the
			// newly resolved versions.
			gitCommit(git, workingDir, "[Release] Prepare for next development iteration");

			runOrFail(git, workingDir, "push");
			runOrFail(git, workingDir, "push", "--tags");

			// Switch dependency properties back to SNAPSHOTs so downstream projects
			// can continue developing against the latest. This is a separate commit
			// because the dependency upgrade is logically distinct from the release.
			runOrFail(mvn, workingDir,
					"org.codehaus.mojo:versions-maven-plugin:update-properties",
					"-DallowSnapshots=true");
			runOrFail(git, workingDir, "clean", "-fdx");
			commitDependencyChangesIfAny(git, workingDir);

			// Publish the SNAPSHOT so downstream projects can resolve the latest
			runOrFail(mvn, workingDir, "clean", "deploy", "-DskipTests");

		} catch (Exception e) {
			throw new MojoExecutionException(e);
		}
	}

	// Parses top-level <properties> entries whose name ends in .version from
	// pom.xml and returns name -> value. Used to snapshot dependency versions
	// before and after versions-maven-plugin:update-properties so we can tell
	// upgrades apart from allowDowngrade-driven downgrades.
	protected Map<String, String> extractVersionProperties(File pomFile) throws Exception {
		Map<String, String> versions = new LinkedHashMap<>();
		if (!pomFile.exists()) {
			return versions;
		}
		String content = readFile(pomFile);
		Pattern p = Pattern.compile("<([\\w][\\w.-]*\\.version)>([^<]+)</\\1>");
		Matcher m = p.matcher(content);
		while (m.find()) {
			versions.put(m.group(1), m.group(2).trim());
		}
		return versions;
	}

	private boolean hasUpgradedDependencies(Map<String, String> before, Map<String, String> after) {
		for (Map.Entry<String, String> e : after.entrySet()) {
			String oldV = before.get(e.getKey());
			if (oldV == null) {
				continue;
			}
			if (isUpgrade(oldV, e.getValue())) {
				getLog().info("Dependency upgrade: " + e.getKey() + " " + oldV + " -> " + e.getValue());
				return true;
			}
		}
		return false;
	}

	// Component-wise numeric comparison after stripping -SNAPSHOT. Returns
	// true only when newV is strictly greater than oldV. Non-numeric parts
	// compare as 0, which is safe: unrecognized version schemes won't be
	// treated as upgrades and won't trigger a spurious release.
	protected boolean isUpgrade(String oldV, String newV) {
		String[] oldParts = oldV.replace("-SNAPSHOT", "").split("\\.");
		String[] newParts = newV.replace("-SNAPSHOT", "").split("\\.");
		int len = Math.max(oldParts.length, newParts.length);
		for (int i = 0; i < len; i++) {
			int o = i < oldParts.length ? parseIntSafe(oldParts[i]) : 0;
			int n = i < newParts.length ? parseIntSafe(newParts[i]) : 0;
			if (n > o) {
				return true;
			}
			if (n < o) {
				return false;
			}
		}
		return false;
	}

	private int parseIntSafe(String s) {
		try {
			return Integer.parseInt(s);
		} catch (NumberFormatException e) {
			return 0;
		}
	}

	// Finds the most recent [Release] commit in this directory and checks if any
	// files changed since then. All commits made by this plugin are prefixed with
	// [Release], so one search always finds the end of the last release cycle.
	private boolean hasSourceChanges(GitRunner git, String workingDir) throws Exception {
		String lastReleaseCommit = git.runAndCapture(workingDir, "log", "--oneline", "-1",
				"--grep=\\[Release\\]", "--", ".");
		if (lastReleaseCommit.isEmpty()) {
			getLog().info("No previous release commits found, treating as new project");
			return true;
		}
		String sha = lastReleaseCommit.split(" ")[0];
		getLog().info("Last release commit: " + lastReleaseCommit);
		String diff = git.runAndCapture(workingDir, "diff", sha + "..HEAD", "--name-only", "--", ".");
		return !diff.isEmpty();
	}

	private void mvnPhase(MavenRunner mvn, String workingDir, String preparationGoals) throws Exception {
		String[] goals = preparationGoals.split(",");
		String[] args = new String[goals.length];
		for (int i = 0; i < goals.length; i++) {
			args[i] = goals[i];
		}
		runOrFail(mvn, workingDir, args);
	}

	// On failure, prints git status so the user can see what went wrong
	private void gitCommit(GitRunner git, String workingDir, String message) throws Exception {
		try {
			runOrFail(git, workingDir, "add", ".");
			runOrFail(git, workingDir, "commit", "-m", message);
		} catch (Exception e) {
			git.run(workingDir, "status");
			throw new Exception(e);
		}
	}

	// Deletes local tag first so failed builds can be restarted without
	// "tag already exists" errors
	private void gitTag(GitRunner git, String workingDir, String tag) throws Exception {
		git.run(workingDir, "tag", "-d", tag);
		runOrFail(git, workingDir, "tag", tag);
	}

	private void commitDependencyChangesIfAny(GitRunner git, String workingDir) throws Exception {
		int exitCode = git.run(workingDir, "diff", "--quiet", "HEAD", "--", ".", ":(exclude)*.bat");
		if (exitCode != 0) {
			getLog().info("Dependency versions changed, committing");
			git.run(workingDir, "add", ".");
			runOrFail(git, workingDir, "commit", "-m", "[Release] Upgrading dependency versions");
			runOrFail(git, workingDir, "push");
		} else {
			getLog().info("No dependency changes to commit");
		}
	}

	// Rewrites image tags in a values.yaml file using pom property values
	// resolved by versions-maven-plugin. Each imageTagMap entry is
	// <pom-property> -> <values.yaml service block key>: the method looks
	// up the property value, finds the service block under `images:` in
	// values.yaml, and replaces the `tag:` line under it.
	//
	// Reads property values directly from pom.xml on disk rather than from
	// MavenProject.getProperties(). The MavenProject object is populated
	// at mojo invocation and is NOT refreshed when the nested
	// versions-maven-plugin:update-properties run modifies pom.xml earlier
	// in the release flow, so project.getProperties() returns stale
	// pre-update values. Reading the file directly picks up the fresh
	// release versions written by versions-maven-plugin.
	//
	// This is a line-based rewrite, not a full YAML parse, so it preserves
	// comments and formatting. Assumptions about the values.yaml layout:
	//   - Service blocks live under `images:` at 2-space indent: `  <key>:`
	//   - Each block has a `tag:` line at 4-space indent: `    tag: <value>`
	//   - The rewrite always emits the value as a quoted string
	//     (`    tag: "<value>"`). This is required because bare semver-like
	//     tokens are parsed as YAML floats: `1.10` becomes 1.1 (trailing zero
	//     stripped), `2.0` becomes 2, etc. Helm then templates the float back
	//     to a string and produces image refs pointing at tags that never
	//     existed. Quoting forces string interpretation.
	//
	// Fails loudly if a pom property has no value, if the service block is
	// missing from values.yaml, or if the tag line is missing. Silent
	// fallthrough would produce a chart that references stale tags.
	protected void updateValuesYaml(File projectDir, File valuesYaml,
			Map<String, String> imageTagMap) throws Exception {
		if (!valuesYaml.exists()) {
			throw new Exception("values.yaml not found at " + valuesYaml.getAbsolutePath());
		}
		File pomFile = new File(projectDir, "pom.xml");
		if (!pomFile.exists()) {
			throw new Exception("pom.xml not found at " + pomFile.getAbsolutePath());
		}
		String pomContent = readFile(pomFile);
		String content = readFile(valuesYaml);
		String[] lines = content.split("\n", -1);

		for (Map.Entry<String, String> entry : imageTagMap.entrySet()) {
			String pomProperty = entry.getKey();
			String serviceKey = entry.getValue();
			// Extract <pomProperty>VALUE</pomProperty> from pom.xml on disk.
			Pattern p = Pattern.compile("<" + Pattern.quote(pomProperty) + ">([^<]+)</"
					+ Pattern.quote(pomProperty) + ">");
			Matcher m = p.matcher(pomContent);
			if (!m.find()) {
				throw new Exception("pom property " + pomProperty + " not found in " + pomFile.getName());
			}
			String resolvedVersion = m.group(1).trim();
			if (resolvedVersion.isEmpty()) {
				throw new Exception("pom property " + pomProperty
						+ " has empty value in " + pomFile.getName());
			}
			if (resolvedVersion.endsWith("-SNAPSHOT")) {
				throw new Exception("pom property " + pomProperty + " is still a SNAPSHOT ("
						+ resolvedVersion + ") — versions-maven-plugin with -DallowSnapshots=false"
						+ " should have resolved it to a release version");
			}

			// Locate `  <serviceKey>:` line (exact 2-space indent)
			String blockHeader = "  " + serviceKey + ":";
			int blockLineIdx = -1;
			for (int i = 0; i < lines.length; i++) {
				if (lines[i].equals(blockHeader) || lines[i].startsWith(blockHeader + " ")) {
					blockLineIdx = i;
					break;
				}
			}
			if (blockLineIdx < 0) {
				throw new Exception("service block " + blockHeader
						+ " not found in " + valuesYaml.getName());
			}

			// Scan forward for the `    tag:` line, stopping if we exit
			// the block (dedent back to 2-space or less, non-blank)
			int tagLineIdx = -1;
			for (int i = blockLineIdx + 1; i < lines.length; i++) {
				String line = lines[i];
				if (line.startsWith("    tag:")) {
					tagLineIdx = i;
					break;
				}
				// End of block: next non-blank line at 2-space indent or less
				if (!line.isEmpty() && !line.startsWith("    ") && !line.startsWith("\t")) {
					break;
				}
			}
			if (tagLineIdx < 0) {
				throw new Exception("no `    tag:` line found under " + blockHeader
						+ " in " + valuesYaml.getName());
			}
			lines[tagLineIdx] = "    tag: \"" + resolvedVersion + "\"";
			getLog().info("values.yaml: " + serviceKey + ".tag = " + resolvedVersion
					+ " (from " + pomProperty + ")");
		}

		writeFile(valuesYaml, String.join("\n", lines));
	}

	// Recursively finds files matching fileName under the project directory and
	// does a string replacement. Used because the same version appears in pom.xml
	// (Maven), MANIFEST.MF (OSGi), and feature.xml (Eclipse) across parent and
	// child modules.
	protected void updateVersion(File project, String start, String currentVersionEnd, String nextVersionEnd,
			String fileName) throws Exception {
		String currentVersionSearchTerm = start + currentVersionEnd;
		String nextVersionSearchTerm = start + nextVersionEnd;

		ArrayList<File> fileList = recursivelyListFiles(project, fileName);
		List<File> filteredList = fileList.stream().filter(f -> (f.getName().contentEquals(fileName)))
				.collect(Collectors.toList());
		for (File f : filteredList) {
			String content = readFile(f);
			// For pom.xml, replace only the first occurrence so we update the
			// top-level project <version> without touching plugin self-references
			// in <build><plugins>, which otherwise match the same literal.
			if (fileName.equals("pom.xml")) {
				int idx = content.indexOf(currentVersionSearchTerm);
				if (idx >= 0) {
					content = content.substring(0, idx) + nextVersionSearchTerm
							+ content.substring(idx + currentVersionSearchTerm.length());
				}
			} else {
				content = content.replace(currentVersionSearchTerm, nextVersionSearchTerm);
			}
			writeFile(f, content);
		}
	}

	protected ArrayList<File> recursivelyListFiles(File aDir, String extension) {
		ArrayList<File> theFiles = new ArrayList<File>();
		if (aDir.exists()) {
			for (String s : aDir.list()) {
				File tempFile = new File(aDir.getAbsolutePath() + File.separator + s);
				if (tempFile.isDirectory()) {
					theFiles.addAll(recursivelyListFiles(tempFile, extension));
				} else if (tempFile.getAbsolutePath().toLowerCase().endsWith(extension.toLowerCase())) {
					theFiles.add(tempFile);
				}
			}
		}
		return theFiles;
	}

	protected void writeFile(File aFile, String content) throws Exception {
		PrintWriter aPrintWriter = new PrintWriter(aFile, StandardCharsets.UTF_8);
		aPrintWriter.print(content);
		aPrintWriter.flush();
		aPrintWriter.close();
	}

	protected String readFile(File aFile) throws Exception {
		return new String(Files.readAllBytes(Paths.get(aFile.toURI())), StandardCharsets.UTF_8);
	}

	private void runOrFail(ProcessRunner runner, String workingDir, String... args) throws Exception {
		int exitCode = runner.run(workingDir, args);
		if (exitCode != 0) {
			throw new Exception("Command failed with exit code " + exitCode + ": " + String.join(" ", args));
		}
	}
}
