package org.farhan.mbt.maven;

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

			// Step 3: Prepare release (tag, deploy, bump to next SNAPSHOT)
			runOrFail(mvn, workingDir,
					"org.farhan:sheep-dog-mgmt-maven-plugin:prepare",
					"-DpreparationGoals=" + preparationGoals);

			// Step 4: Push commits and tags
			runOrFail(git, workingDir, "push");
			runOrFail(git, workingDir, "push", "--tags");

			// Step 5: Update dependency properties to SNAPSHOT versions
			runOrFail(mvn, workingDir,
					"org.codehaus.mojo:versions-maven-plugin:update-properties",
					"-DallowSnapshots=true");
			runOrFail(git, workingDir, "clean", "-fdx");

			// Step 6: Commit dependency version changes if any
			commitDependencyChangesIfAny(git, workingDir);

			// Step 7: Deploy SNAPSHOT
			runOrFail(mvn, workingDir, "clean", "deploy", "-DskipTests");

		} catch (Exception e) {
			throw new MojoExecutionException(e);
		}
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

	private void runOrFail(ProcessRunner runner, String workingDir, String... args) throws Exception {
		int exitCode = runner.run(workingDir, args);
		if (exitCode != 0) {
			throw new Exception("Command failed with exit code " + exitCode + ": " + String.join(" ", args));
		}
	}
}
