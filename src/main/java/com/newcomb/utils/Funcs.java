package com.newcomb.utils;

import java.util.Scanner;

public class Funcs {
    private String className;
    private int classNum;
    private static Scanner scanner = new Scanner(System.in);

    public Funcs(){
        this("default name",0);
    }
    public Funcs(String className){
        this(className,111);
    }
    public Funcs(String className,int classNum){
        this.className = className;
        this.classNum = classNum;
    }
    public String saySomething(){
        System.out.println("What would you like to say?");
        String userStatement = scanner.nextLine();
        System.out.println("My name is " + this.className + " and my num is " + this.classNum);
        return userStatement;
    }
}
