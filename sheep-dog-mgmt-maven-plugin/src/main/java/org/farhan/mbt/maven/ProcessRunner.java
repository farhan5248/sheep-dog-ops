package org.farhan.mbt.maven;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.List;

import org.apache.maven.plugin.logging.Log;

public class ProcessRunner {

	private Log log;

	public ProcessRunner(Log log) {
		this.log = log;
	}

	protected static boolean isWindows() {
		return System.getProperty("os.name").toLowerCase().contains("win");
	}

	protected List<String> buildCommand(String... args) {
		List<String> command = new ArrayList<>();
		for (String arg : args) {
			command.add(arg);
		}
		return command;
	}

	public int run(String workingDirectory, String... args) throws Exception {
		List<String> command = buildCommand(args);

		ProcessBuilder pb = new ProcessBuilder(command);
		pb.directory(new File(workingDirectory));
		pb.redirectErrorStream(true);

		log.info("Running: " + String.join(" ", command));

		Process process = pb.start();
		process.getOutputStream().close();
		try (BufferedReader reader = new BufferedReader(
				new InputStreamReader(process.getInputStream()))) {
			String line;
			while ((line = reader.readLine()) != null) {
				log.info(line);
			}
		}
		return process.waitFor();
	}

	public String runAndCapture(String workingDirectory, String... args) throws Exception {
		List<String> command = buildCommand(args);

		ProcessBuilder pb = new ProcessBuilder(command);
		pb.directory(new File(workingDirectory));
		pb.redirectErrorStream(true);

		log.info("Running: " + String.join(" ", command));

		Process process = pb.start();
		process.getOutputStream().close();
		StringBuilder output = new StringBuilder();
		try (BufferedReader reader = new BufferedReader(
				new InputStreamReader(process.getInputStream()))) {
			String line;
			while ((line = reader.readLine()) != null) {
				output.append(line).append("\n");
			}
		}
		process.waitFor();
		return output.toString().trim();
	}

	protected Log getLog() {
		return log;
	}
}
