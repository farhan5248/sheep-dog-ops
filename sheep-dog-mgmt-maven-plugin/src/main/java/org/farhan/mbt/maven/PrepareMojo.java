package org.farhan.mbt.maven;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
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
import org.apache.maven.plugins.annotations.LifecyclePhase;
import org.apache.maven.plugins.annotations.Mojo;
import org.apache.maven.plugins.annotations.Parameter;
import org.apache.maven.project.MavenProject;

@Mojo(name = "prepare", defaultPhase = LifecyclePhase.POST_INTEGRATION_TEST)
public class PrepareMojo extends AbstractMojo {

	@Parameter(defaultValue = "${project}", readonly = true)
	public MavenProject project;

	@Parameter(property = "preparationGoals", defaultValue = "deploy")
	public String preparationGoals;

	@Override
	public void execute() throws MojoExecutionException, MojoFailureException {
		try {
			if (!project.getModules().isEmpty()) {
				String cv = project.getVersion().replace("-SNAPSHOT", "");
				getLog().info("current version: " + cv);

				updateVersion(project.getBasedir(), "<version>", cv + "-SNAPSHOT</version>", cv + "</version>",
						"pom.xml");
				updateVersion(project.getBasedir(), "Bundle-Version: ", cv + ".qualifier", cv + "", "MANIFEST.MF");
				updateVersion(project.getBasedir(), "version=\"", cv + ".qualifier\"", cv + "\"", "feature.xml");
				getLog().info("Commit changes");
				gitCommit("prepare release " + project.getArtifactId() + "-" + cv);
				getLog().info("Tag changes");
				gitTag(project.getArtifactId() + "-" + cv);

				getLog().info("Run Maven");
				mvnPhase(preparationGoals);

				String[] cvParts = cv.split("\\.");
				String nv = cvParts[0] + "." + String.valueOf(Integer.parseInt(cvParts[1]) + 1) + "." + cvParts[2];
				getLog().info("next version: " + nv);

				updateVersion(project.getBasedir(), "<version>", cv + "</version>", nv + "-SNAPSHOT</version>",
						"pom.xml");
				updateVersion(project.getBasedir(), "Bundle-Version: ", cv + "", nv + ".qualifier", "MANIFEST.MF");
				updateVersion(project.getBasedir(), "version=\"", cv + "\"", nv + ".qualifier\"", "feature.xml");
				getLog().info("Commit changes");
				gitCommit("prepare for next development iteration");

			}
		} catch (Exception e) {
			throw new MojoExecutionException(e);
		}
	}

	private void mvnPhase(String preparationGoals) throws Exception {
		String[] goals = preparationGoals.split(",");
		String[] mvnCommand = new String[goals.length + 1];
        if (System.getProperty("os.name").toLowerCase().contains("win")) {
    		mvnCommand[0] = "mvn.cmd";
        } else {
    		mvnCommand[0] = "mvn";
        }
		for (int i = 0; i < goals.length; i++) {
			mvnCommand[i + 1] = goals[i];
		}
		runCommand(mvnCommand);
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

	protected void gitCommit(String message) throws Exception {
		try {
			String[] addCommand = { "git", "add", "*" };
			runCommand(addCommand);
			String[] commitCommand = { "git", "commit", "-m", message };
			runCommand(commitCommand);
		} catch (Exception e) {
			String[] addCommand = { "git", "status" };
			runCommand(addCommand);
			throw new Exception(e);
		}
	}

	protected void gitTag(String tag) throws Exception {
		String[] tagCommand = { "git", "tag", tag };
		runCommand(tagCommand);
	}

	protected void runCommand(String[] command) throws Exception {
		ProcessBuilder processBuilder = new ProcessBuilder(command);
		Process process = processBuilder.start();
		BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
		String line;
		while ((line = reader.readLine()) != null) {
			getLog().info(line);
		}
		if (process.waitFor() != 0) {
			reader = new BufferedReader(new InputStreamReader(process.getErrorStream()));
			while ((line = reader.readLine()) != null) {
				getLog().error(line);
			}
			throw new Exception("Command line execution failed");
		}
	}
}
