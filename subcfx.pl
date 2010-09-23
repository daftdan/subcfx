#!/usr/bin/perl
# subcfx - take user input, create a PBS submission script for ANSYS CFX, submit the job
# DEC and JC of OCSL

use warnings;
use strict;
use Data::Dumper;

## Defaults
my $version		= 12;
my $cpus_to_use		= 2;
my $ccl_file		= "";
my $restart_file	= "";
my $edit_command_line	= "";
my $ready_to_run	= 0;
my $default_queue	= "cfx";
my $license_type	= "acfx_par_proc";
my $cfx_version;
my %available_versions;
foreach my $executable_name (</prg/ansys/v*/CFX/bin/cfx5solve>) {
	if($executable_name =~ m!/prg/ansys/v([.\d]+)/CFX/bin/cfx5solve!) {
		$cfx_version = $1;
		chomp $cfx_version;
		$available_versions{$cfx_version} = $executable_name;
	}
}

#~ my %available_versions = (
    #~ 12.1    => "/prg/ansys/v121/CFX/bin/cfx5solve",
    #~ 12      => "/prg/ansys/v120/CFX/bin/cfx5solve",
    #~ "11sp1" => "/prg/ansys/v110/CFX/bin/cfx5solve",
    #~ 11      => "/prg/ansys/v110/CFX.sp0/bin/cfx5solve",
    #~ 10      => "/prg/ansys/v100/CFX-10.0/bin/cfx5solve",
#~ );


my $max_cpus = 32;

my $input_file = select_input_file("def");

while(!$ready_to_run) {

    display_status();
    my $input = <STDIN>;
    chomp $input;
    $input = lc $input;
    if($input =~ /^n/i) {
        $input_file = select_input_file("def");
    }

    elsif($input =~ /^v/i) {
        $version = select_version();
    }
    elsif($input =~ /^cp/i) {
        $cpus_to_use = select_cpu_count();
    }
    elsif($input =~ /^cc/i) {
        $ccl_file = select_input_file("ccl");
    }
	elsif($input =~ /^r/i) {
		$restart_file = select_input_file("res");
	}
	elsif($input =~ /^cm/i) {
		$edit_command_line = $edit_command_line ? "" : "True";
	}
	elsif($input =~ /^li/i) {
		# toggle between the two strings "anshpc_pack" and "acfx_par_proc"
		$license_type = $license_type eq "acfx_par_proc"?"anshpc_pack":"acfx_par_proc";
	}
	elsif($input =~ /^g/i) {
		if($input_file and $cpus_to_use and $version) {
			launch_job();
		}
		else {
			print "You need to specify at least an input file, the number of CPUs, and the CFX version.\n";
			print "Press [ENTER] to continue.\n";
		my $foo = <STDIN>;
		}
       
	}
	elsif($input =~ /^(exit|quit)/i) {
		exit(0);
	}
}

#Create the script to submit to PBS.
sub launch_job {
    (my $job_name = $input_file) =~ s/\.m?def$//i;
    my $launch_filename = $job_name . ".qsub.sh";
    open(my $fh, ">", $launch_filename)
        or die "Unable to open $launch_filename: $!\n";

	#~ my $cpu_line;
	#~ if(1 == $cpus_to_use) {
		#~ $cpu_line = "#PBS -l nodes=1:ppn=1\n";
	#~ } else {
		#~ my $num_machines = int($cpus_to_use / 2);
		#~ if($cpus_to_use == 2*$num_machines) {
			#~ $cpu_line = "#PBS -l nodes=$num_machines:ppn=2";
		#~ } else {
			#~ $cpu_line = "#PBS -l nodes=$num_machines:ppn=2+1:ppn=1";
		#~ }
	#~ }
	
	my $license_resources;
	if ($license_type eq "acfx_par_proc") {
		$license_resources = "acfx_solver%acfx_par_proc+" . $cpus_to_use;
	} elsif ($license_type eq "ans_hpc_pack") {
		if ($cpus_to_use <= 8) {
			$license_resources = "acfx_solver%ans_hpc_pack";
		} else {
			$license_resources = "acfx_solver%ans_hpc_pack+2";
		}
	}

	my $additional_options = "";
	$additional_options .= " -ccl $ccl_file"     if($ccl_file);
	$additional_options .= " -ini $restart_file" if($restart_file);

	my $prog_to_run = $available_versions{$version};

	print $fh <<"EOSCRIPT";
#!/bin/sh
#
#PBS -N $job_name
#PBS -d $ENV{PWD}
#PBS -q $default_queue
#PBS -W umask=006
#PBS -p 0
#PBS -l nodes=$cpus_to_use
#PBS -l gres=$license_resources

# go to directory in which job was submitted
#cd \$PBS_O_WORKDIR
$prog_to_run -def \"$input_file\" -preferred-license $license_type $additional_options -par-dist "\$(cat \$PBS_NODEFILE)" -start-method "HP MPI Distributed Parallel"
EOSCRIPT
     
    close($fh);

	# edit the script if requested, use $EDITOR if possible, scite otherwise.
	if($edit_command_line) {
		if($ENV{EDITOR}) {
			system($ENV{EDITOR}, $launch_filename);
		}
		else {
			system("scite", $launch_filename);
		}
	}

	# Submit the job to PBS
	#~ chmod 0775, $launch_filename;
	system("qsub", $launch_filename);
	exit();
}


sub display_status {
    system('clear');
    no warnings "uninitialized";
    print <<EOMESSAGE;

CFX Job Submission: 2010-09-21

Submission Status:

Job Name              (nam): $input_file
CFX Version           (ver): $version
Number of CPUs        (cpu): $cpus_to_use
CCL File              (ccl): $ccl_file
Restart File          (res): $restart_file
Edit CFX Command Line (cmd): $edit_command_line
parallel license type (lic): $license_type

To edit the job options, enter one of the following:
"job", "ver", "cpu", "ccl", "res", "cmd", or "go" to
submit the job. "exit" will exit.
EOMESSAGE
}

sub select_input_file {
    my $extension = shift;
    system('clear');
    print "\n\n\n\nPlease select the appropriate file from the list below\n";
    my @input_files = (<*$extension>);

    if(scalar (@input_files) == 0) {
        print "\nNo files with an extension of $extension found. Press [ENTER] to continue.\n";
        my $foo = <STDIN>;
        return undef;
    } elsif(scalar (@input_files) == 1) {
        print "\nAutomatically selecting " . $input_files[0] . ". Press [ENTER] to continue.\n";
        my $foo = <STDIN>;
        return($input_files[0]);
    }
    #Show a list of available files
    for(my $i=0 ; $i <= $#input_files ; $i++) {
        my $t = $i+1;
        print "$t) " . $input_files[$i] . "\n";
    }

    print "\n";
    my $selected_input_file;
    until ($selected_input_file) {
        my $user_input = <STDIN>;
        chomp $user_input;
        $user_input =~ s/\D*//g; # Numbers only, pleases
        if(length($user_input) and $user_input >= 1 and $user_input <= $#input_files+1) {
            my $index = $user_input - 1;
            $selected_input_file = $input_files[$index];
        }
        else {
            warn "Please select a number between 1 and $#input_files\n";
        }
    }
    return $selected_input_file;
}

sub select_version {
    system('clear');
    print "\n\n\n\nPlease select the required CFX version\n";
    print "Available versions: ", join(", ", sort keys %available_versions), "\n";
    my $selected_version;
    until ($selected_version) {
        my $user_input = <STDIN>;
        chomp $user_input;
        #~$user_input =~ s/\D*//g; # Numbers only, pleases

        if(exists($available_versions{$user_input})) {
            $selected_version = $user_input
        }
        else {
            warn "Please select a version from the list\n";
        }
    }
    return $selected_version;
}

sub select_cpu_count {
    system('clear');
    print "\n\n\n\nPlease select the required number of CPUs (1-$max_cpus)\n";
    my $selected_count;
    until ($selected_count) {
        my $user_input = <STDIN>;
        chomp $user_input;
        $user_input =~ s/\D*//g; # Numbers only, pleases

        if($user_input and 1 <= $user_input and $user_input <= $max_cpus) {
            $selected_count = $user_input
        }
        else {
            warn "Please select a valid number between 1 and $max_cpus \n";
        }
    }
	$license_type = "anshpc_pack" if ($selected_count > 16);
	return $selected_count;
}
