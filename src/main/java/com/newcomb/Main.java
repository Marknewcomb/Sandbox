package com.newcomb;

import com.newcomb.utils.Funcs;

public class Main {
    public static void main(String[] args) {
        System.out.println("Java Testing");
        if(args.length > 0){
            for(var i: args){
                System.out.println(i);
            }
        }
        else{
            System.out.println("Sorry. There are no args passed in.");
        }
        Funcs funcs = new Funcs();
        String statement = funcs.saySomething();
        System.out.println(statement);
    }

    public static void run(){
        System.out.println("Run function");
    }
}
