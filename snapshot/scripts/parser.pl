#! /usr/bin/perl

use 5.010;
use strict;
use warnings;
use DBI;

my $target = 'api.cf173.dev.las01.vcsops.com';

#CCDB access
my $host = "10.42.240.12";
my $port = "5524";
my $dbname = "appcloud";
my $username = "ccadmin";
my $password = "tauBauWauZZb2";

my $output = "../config/service_config.yml";

my $service = "";
my $plan = "";
my $email = "";
my $service_name = "";

my @service_data;
my $service_data_cnt = 0;
my @service_data_selected;
my $service_data_selected_cnt = 0;
my $instance_count = 10;
my %service_plan;

my $service_instances;
while (<>)
{
  chomp;
  $service_instances.="\'$_\',";
}
chop($service_instances);
#DB Access

my $dbh = DBI->connect("dbi:Pg:dbname = $dbname; host = $host; port = $port", "$username", "$password");
my $query = $dbh->prepare("select services.name,plan,email,service_configs.name from service_configs join users on service_configs.user_id = users.id join services on service_configs.service_id = services.id where service_configs.name in ($service_instances) order by services.name, plan, email;");
my $result = $query->execute();
while (my @line = $query->fetchrow_array())
{
  if ($line[0] =~ /^\s*(mongodb|mysql|postresql|redis)/)
  {
    if (($line[0] ne $service) || ($line[1] ne $plan))
    {
      $service_plan{"$line[0]-$line[1]"} = 1;
      $service = $line[0];
      $plan = $line[1];
    }
    else
    {
      $service_plan{"$line[0]-$line[1]"}++;
    }
    push @service_data, [@line];
    #print "$service_data[$service_data_cnt][0]";
    ++$service_data_cnt;
  }
}

for ( my $i = 0; $i != $service_data_cnt; ++$i)
{
  if ($service_plan{"$service_data[$i][0]-$service_data[$i][1]"} > $instance_count)
  {
    if (int(rand($service_plan{"$service_data[$i][0]-$service_data[$i][1]"})) < $instance_count)
    {
      push @service_data_selected, $service_data[$i];
      $service_data_selected_cnt++;
    }
  }
  else
  {
    push @service_data_selected, $service_data[$i];
    $service_data_selected_cnt++;
  }
}

$service = "";
$plan = "";
open(CONFIG_FILE, ">$output");

print CONFIG_FILE "---\n";
print CONFIG_FILE "target: $target\n";
print CONFIG_FILE "services:\n";
for (my $i = 0; $i != $service_data_selected_cnt; ++$i)
{
  if($service_data_selected[$i][0] ne $service)
  {
    print CONFIG_FILE "- name: $service_data_selected[$i][0]\n";
    print CONFIG_FILE "  plans:\n";
    print CONFIG_FILE "  - name: $service_data_selected[$i][1]\n";
    print CONFIG_FILE "    users:\n";
    print CONFIG_FILE "    - email: $service_data_selected[$i][2]\n";
    print CONFIG_FILE "      password: password\n";
    print CONFIG_FILE "      services:\n";
    print CONFIG_FILE "      - service: $service_data_selected[$i][3]\n";
    $service = $service_data_selected[$i][0];
    $plan = $service_data_selected[$i][1];
    $email = $service_data_selected[$i][2];
    $service_name = $service_data_selected[$i][3]
  }
  elsif($service_data_selected[$i][1] ne $plan)
  {
    print CONFIG_FILE "  - name: $service_data_selected[$i][1]\n";
    print CONFIG_FILE "    users:\n";
    print CONFIG_FILE "    - email: $service_data_selected[$i][2]\n";
    print CONFIG_FILE "      password: password\n";
    print CONFIG_FILE "      services:\n";
    print CONFIG_FILE "      - service: $service_data_selected[$i][3]\n";
    $plan = $service_data_selected[$i][1];
    $email = $service_data_selected[$i][2];
    $service_name = $service_data_selected[$i][3]
  }
  elsif($service_data_selected[$i][2] ne $email)
  {
    print CONFIG_FILE "    - email: $service_data_selected[$i][2]\n";
    print CONFIG_FILE "      password: password\n";
    print CONFIG_FILE "      services:\n";
    print CONFIG_FILE "      - service: $service_data_selected[$i][3]\n";
    $email = $service_data_selected[$i][2];
    $service_name = $service_data_selected[$i][3]
  }
  else
  {
    print CONFIG_FILE "      - service: $service_data_selected[$i][3]\n";
    $service_name = $service_data_selected[$i][3]
  }
}
