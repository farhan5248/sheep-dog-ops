package org.farhan.mbt.maven;

import java.io.File;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
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
			// released artifact depends on stable releases, not moving targets
			runOrFail(mvn, workingDir,
					"org.codehaus.mojo:versions-maven-plugin:update-properties",
					"-DallowSnapshots=false");

			// Only release if there's a reason to: either a dependency got a new
			// release version (pom changed above), or someone committed real changes
			// since the last release cycle
			boolean dependencyChange = hasUncommittedChanges(git, workingDir);
			boolean sourceChange = hasSourceChanges(git, workingDir);

			if (!dependencyChange && !sourceChange) {
				getLog().info("No dependency changes and no source changes since last release, skipping");
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

	// After update-properties resolves SNAPSHOTs to releases, any pom.xml diff
	// means a dependency has a new release version. We don't use -DallowDowngrade
	// so update-properties only changes a property if a genuinely newer release
	// exists (e.g. 1.50-SNAPSHOT won't downgrade to 1.49).
	private boolean hasUncommittedChanges(GitRunner git, String workingDir) throws Exception {
		int exitCode = git.run(workingDir, "diff", "--quiet", "HEAD", "--", ".", ":(exclude)*.bat");
		return exitCode != 0;
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
			writeFile(f, readFile(f).replace(currentVersionSearchTerm, nextVersionSearchTerm));
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
