#!/usr/bin/perl

# $Id$

use strict;
use warnings;
use Env;

my %poli;
my %prot;
my %srcp;
my %dstp;
my %srci;
my %dsti;
my %conv;

my $total=0;

### change this value to print more or less entries
my $howmany=10;

### printing function
sub printtop;

# function for adding the item to the hash
sub additem;

my $file=shift;

open(FD,$file);
while(<FD>){
  chomp;

  if(/^id/){
    (my $pid=$_)=~s/.*policy (\d+),.*/$1/;
    additem(\%poli,$pid);
    $total++;
  }

  if (/\d+->\d+/){
    (my $data=$_)=~s/^.+?:(.+?)\/(\d+?)->(.+?)\/(\d+),(\d+),.*/$1 $2 $3 $4 $5/;
    my @dat=split(' ',$data);
    additem(\%prot,$dat[4]);
    additem(\%dstp,$dat[3]);
    additem(\%srcp,$dat[1]);
    additem(\%dsti,$dat[2]);
    additem(\%srci,$dat[0]);
    additem(\%conv,"$dat[0]\-\>$dat[2]");
  }
} 
close(FD);

print "Total sessions seen $total\n";

printtop(\%poli,"policies");
printtop(\%prot,"protocols");
printtop(\%srcp,"source ports");
printtop(\%dstp,"destination ports");
printtop(\%srci,"source IPs");
printtop(\%dsti,"destination IPs");
printtop(\%conv,"conversations (src IP->dst IP)");


### printing function
sub printtop{
  my $tmph=shift;
  my $name=shift;

  if (exists($ENV{"APACHE_PID_FILE"})){
    print "\n<b>Top $howmany (or less) $name:</b>\n";
  }else{
    print "\nTop $howmany (or less) $name:\n";
  } 
  my @tmpa = sort {$tmph->{$b} <=> $tmph->{$a}} keys %$tmph;

  my $max=$howmany;
  $max=$#tmpa+1 if ($#tmpa < $howmany-1);

  for(my $i=0;$i<$max;$i++){
    print $tmpa[$i]." seen in ".$tmph->{$tmpa[$i]}." session(s) - ".(sprintf("%.2f",($tmph->{$tmpa[$i]}/$total*100)))."% of all\n";
  }
}

# function for adding the item to the hash
sub additem{
  my $tmph=shift;
  my $tmpi=shift;

  if (exists($tmph->{$tmpi})){
    $tmph->{$tmpi}++;
  }else{
    $tmph->{$tmpi}=1;
  }
}
