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
			// Step 1: Reset to clean state
			runOrFail(git, workingDir, "reset", "--hard", "HEAD");
			runOrFail(git, workingDir, "clean", "-fdx");
			runOrFail(git, workingDir, "pull");

			// Step 2: Update dependency properties to release versions
			runOrFail(mvn, workingDir,
					"org.codehaus.mojo:versions-maven-plugin:update-properties",
					"-DallowSnapshots=false", "-DallowDowngrade=true");

			// Step 3: Check if release is needed
			boolean dependencyChange = hasUncommittedChanges(git, workingDir);
			boolean sourceChange = hasCommitsSinceLastTag(git, workingDir);

			if (!dependencyChange && !sourceChange) {
				getLog().info("No dependency changes and no source changes since last tag, skipping release");
				return;
			}

			if (dependencyChange) {
				getLog().info("Dependency changes detected, releasing");
			}
			if (sourceChange) {
				getLog().info("Source changes since last tag, releasing");
			}

			// Step 4: Prepare release (version update, commit, tag, deploy, bump)
			String cv = project.getVersion().replace("-SNAPSHOT", "");
			getLog().info("current version: " + cv);

			updateVersion(project.getBasedir(), "<version>", cv + "-SNAPSHOT</version>", cv + "</version>", "pom.xml");
			updateVersion(project.getBasedir(), "Bundle-Version: ", cv + ".qualifier", cv + "", "MANIFEST.MF");
			updateVersion(project.getBasedir(), "version=\"", cv + ".qualifier\"", cv + "\"", "feature.xml");
			gitCommit(git, workingDir, "prepare release " + project.getArtifactId() + "-" + cv);
			gitTag(git, workingDir, project.getArtifactId() + "-" + cv);

			getLog().info("Run Maven deploy");
			mvnPhase(mvn, workingDir, preparationGoals);

			String[] cvParts = cv.split("\\.");
			String nv;
			if (cvParts.length >= 3) {
				nv = cvParts[0] + "." + cvParts[1] + "." + String.valueOf(Integer.parseInt(cvParts[2]) + 1);
			} else {
				nv = cvParts[0] + "." + String.valueOf(Integer.parseInt(cvParts[1]) + 1);
			}
			getLog().info("next version: " + nv);

			updateVersion(project.getBasedir(), "<version>", cv + "</version>", nv + "-SNAPSHOT</version>", "pom.xml");
			updateVersion(project.getBasedir(), "Bundle-Version: ", cv + "", nv + ".qualifier", "MANIFEST.MF");
			updateVersion(project.getBasedir(), "version=\"", cv + "\"", nv + ".qualifier\"", "feature.xml");
			gitCommit(git, workingDir, "prepare for next development iteration");

			// Step 5: Push commits and tags
			runOrFail(git, workingDir, "push");
			runOrFail(git, workingDir, "push", "--tags");

			// Step 6: Update dependency properties to SNAPSHOT versions
			runOrFail(mvn, workingDir,
					"org.codehaus.mojo:versions-maven-plugin:update-properties",
					"-DallowSnapshots=true");
			runOrFail(git, workingDir, "clean", "-fdx");

			// Step 7: Commit dependency version changes if any
			commitDependencyChangesIfAny(git, workingDir);

			// Step 8: Deploy SNAPSHOT
			runOrFail(mvn, workingDir, "clean", "deploy", "-DskipTests");

		} catch (Exception e) {
			throw new MojoExecutionException(e);
		}
	}

	private boolean hasUncommittedChanges(GitRunner git, String workingDir) throws Exception {
		int exitCode = git.run(workingDir, "diff", "--quiet", "HEAD", "--", ".", ":(exclude)*.bat");
		return exitCode != 0;
	}

	private boolean hasCommitsSinceLastTag(GitRunner git, String workingDir) throws Exception {
		String tag = project.getArtifactId() + "-" + project.getVersion().replace("-SNAPSHOT", "");
		// Check if previous release tag exists
		String prevTag = getPreviousTag(tag);
		int exitCode = git.run(workingDir, "rev-parse", "--verify", prevTag);
		if (exitCode != 0) {
			getLog().info("No previous tag " + prevTag + " found, treating as new project");
			return true;
		}
		// Check if there are commits since that tag
		exitCode = git.run(workingDir, "log", prevTag + "..HEAD", "--oneline", "--", ".");
		return exitCode == 0;
	}

	private String getPreviousTag(String currentTag) {
		// currentTag is like "sheep-dog-grammar-1.44" — the previous release was 1.43
		String prefix = currentTag.substring(0, currentTag.lastIndexOf("-") + 1);
		String version = currentTag.substring(currentTag.lastIndexOf("-") + 1);
		String[] parts = version.split("\\.");
		if (parts.length >= 3) {
			int patch = Integer.parseInt(parts[2]) - 1;
			return prefix + parts[0] + "." + parts[1] + "." + patch;
		} else {
			int minor = Integer.parseInt(parts[1]) - 1;
			return prefix + parts[0] + "." + minor;
		}
	}

	private void mvnPhase(MavenRunner mvn, String workingDir, String preparationGoals) throws Exception {
		String[] goals = preparationGoals.split(",");
		String[] args = new String[goals.length];
		for (int i = 0; i < goals.length; i++) {
			args[i] = goals[i];
		}
		runOrFail(mvn, workingDir, args);
	}

	private void gitCommit(GitRunner git, String workingDir, String message) throws Exception {
		try {
			runOrFail(git, workingDir, "add", ".");
			runOrFail(git, workingDir, "commit", "-m", message);
		} catch (Exception e) {
			git.run(workingDir, "status");
			throw new Exception(e);
		}
	}

	private void gitTag(GitRunner git, String workingDir, String tag) throws Exception {
		// Delete local tag if it exists (supports restarting failed builds)
		git.run(workingDir, "tag", "-d", tag);
		runOrFail(git, workingDir, "tag", tag);
	}

	private void commitDependencyChangesIfAny(GitRunner git, String workingDir) throws Exception {
		int exitCode = git.run(workingDir, "diff", "--quiet", "HEAD", "--", ".", ":(exclude)*.bat");
		if (exitCode != 0) {
			getLog().info("Dependency versions changed, committing");
			git.run(workingDir, "add", ".");
			runOrFail(git, workingDir, "commit", "-m", "Upgrading dependency versions");
			runOrFail(git, workingDir, "push");
		} else {
			getLog().info("No dependency changes to commit");
		}
	}

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
