package org.farhan.mbt.maven;

import java.util.ArrayList;
import java.util.List;

import org.apache.maven.plugin.logging.Log;

public class MavenRunner extends ProcessRunner {

	public MavenRunner(Log log) {
		super(log);
	}

	@Override
	protected List<String> buildCommand(String... args) {
		List<String> command = new ArrayList<>();
		command.add(isWindows() ? "mvn.cmd" : "mvn");
		for (String arg : args) {
			command.add(arg);
		}
		return command;
	}
}
