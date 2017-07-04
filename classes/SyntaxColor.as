﻿/*******************************************************************************
 * This is the copyright work of The MITRE Corporation, and was produced for the 
 * U. S. Government under Contract Number DTFAWA-10-C-00080.
 * 
 * For further information, please contact The MITRE Corporation, Contracts Office, 
 * 7515 Colshire Drive, McLean, VA  22102-7539, (703) 983-6000.
 * 
 * Copyright 2014 The MITRE Corporation
 *
 * Approved for Public Release; Distribution Unlimited. 14-0584
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 * http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 ******************************************************************************/

package classes {
	import flash.text.TextFormat;
	import classes.WrappedLineUtils;
	import classes.SolarizedPalette;
	import com.inruntime.utils.*;

	
	public class SyntaxColor {
		private static var $:Global = Global.getInstance();
		private static var indents:int;
		private static var goalLine:Boolean;
		private static var branchLine:Boolean;
		private static var operator:String;
		private static var lineLabel:String;
		private static var time:String;
		private static var threadLabel:String;
		private static var errorFixed:Boolean;
		private static var chunkNames:Array = [];
		
		private static const black:TextFormat = new TextFormat();
		private static const grey:TextFormat = new TextFormat();
		private static const blue:TextFormat = new TextFormat();
		private static const cyan:TextFormat = new TextFormat();
		private static const orange:TextFormat = new TextFormat();
		private static const green:TextFormat = new TextFormat();
		private static const red:TextFormat = new TextFormat();
		private static const magenta:TextFormat = new TextFormat();
		private static const errorred:TextFormat = new TextFormat();
		
		static var methods:Array = ["goal", "also", "as"];
		static var branches:Array = ["if", "endif", "goto", "createstate", "setstate"];
		static var errorInLine:Boolean = false;

		static var typing:Boolean = false;
		
		black.color = SolarizedPalette.black;
		cyan.color = SolarizedPalette.cyan;
		grey.color = SolarizedPalette.grey;
		blue.color = SolarizedPalette.blue;
		orange.color = SolarizedPalette.orange;
		green.color = SolarizedPalette.green;
		red.color = SolarizedPalette.red;
		magenta.color = SolarizedPalette.magenta;
		errorred.color = SolarizedPalette.errorred;
		
		public static function solarizeAll():void{
			var codeLines:Array = $.codeTxt.text.split("\r");
			var beginIndex:int = 0;
			var endIndex:int = codeLines[0].length;
			for (var key:Object in $.errors) delete $.errors[key];  //clear out all $.errors

			for (var lineIndex:int = 0; lineIndex < codeLines.length; lineIndex++ ) {	
				var line = codeLines[lineIndex];
				endIndex = beginIndex + line.length;
				if (trim(line) != "") solarizeLineNum(lineIndex, beginIndex, endIndex);
				beginIndex = endIndex + 1;
			}
		}
		
		
		public static function solarizeSelectedLine():Boolean {
			trace("solarizeSelectedLine");
			typing = true;
			//get line number based on caret position
			var lineNumber = WrappedLineUtils.getLineNumber($.codeTxt, $.codeTxt.caretIndex);
				lineNumber--;
			var begindex = WrappedLineUtils.getLineIndex($.codeTxt, lineNumber);
			var endex = WrappedLineUtils.getLineEndIndex($.codeTxt, lineNumber);
			
			//chunkErrors are a special case because they can't be identified until after the GomsProcessor initiates WM modeling
			//chunkErrors are identified in WorkingMemory.as, which calls a custom function here (solarizeChunkAtLineNum) to color the errors
			var chunkNamedInError:String = "";
			var errMessage = $.errors[lineNumber];
			if (errMessage != undefined) if (errMessage.indexOf("memory") > -1) {
				var leftAngleIndex = errMessage.indexOf("<");
				var rightAngleIndex = errMessage.indexOf(">");
				chunkNamedInError = errMessage.substring(leftAngleIndex, rightAngleIndex);	
			}	
			
			return (solarizeLineNum(lineNumber, begindex, endex, chunkNamedInError)[6]);
		}
		
		//Purpose:  Color the line specified.  Created for Cog+ functionality
		//Input: line number to be colorized.
		//Output: none.
		//SideEffect: The line should be colored.  Other side effects are TBD.
		public static function solarizeLine(lineNumber:int) {
			//get line number based on caret position
			var begindex = WrappedLineUtils.getLineIndex($.codeTxt, lineNumber);
			var endex = WrappedLineUtils.getLineEndIndex($.codeTxt, lineNumber);
			
			//chunkErrors are a special case because they can't be identified until after the GomsProcessor initiates WM modeling
			//chunkErrors are identified in WorkingMemory.as, which calls a custom function here (solarizeChunkAtLineNum) to color the errors
			var chunkNamedInError:String = "";
			var errMessage = $.errors[lineNumber];
			if (errMessage != undefined) if (errMessage.indexOf("memory") > -1) {
				var leftAngleIndex = errMessage.indexOf("<");
				var rightAngleIndex = errMessage.indexOf(">");
				chunkNamedInError = errMessage.substring(leftAngleIndex, rightAngleIndex);	
			}	
			
			solarizeLineNum(lineNumber, begindex, endex, chunkNamedInError)[6];
		}


		public static function ErrorColorLine(lineNumber:int){
			
			//get line number based on caret position
			var beginIndex = WrappedLineUtils.getLineIndex($.codeTxt, lineNumber);
			var endIndex = WrappedLineUtils.getLineEndIndex($.codeTxt, lineNumber);
			
			$.codeTxt.setTextFormat(errorred, beginIndex, endIndex);
		}
		
			
		//0: Number of Indents
		//1: Operator
		//2: Label
		//3: Custom Time (if used)
		//4: Thread Label
		//5: Error in line boolean
		//6: Error fixed in line boolean - the one non-Goms processor calls are looking for
		//7: Array of chunk names "<>"
		
		public static function solarizeLineNum(lineNum:int, beginIndex:int = -1, endIndex:int = -1, chunkNamedInError:String = ""):Array {
			time = "";
			chunkNames.length = 0;
			
			var lineIsInErrors:Boolean = false;
			if ($.errors[lineNum] != undefined) lineIsInErrors = true;
			errorInLine = false;
			
			if(beginIndex == -1) {
				beginIndex = findBeginIndex();
				endIndex = findEndIndex(beginIndex);
			}
			
			var index:int;
			var lineStartIndex:int = beginIndex;
			
			var lineTxt:String = $.codeTxt.text.substring(beginIndex, endIndex);
			if (chunkNamedInError == "") delete $.errors[lineNum];

			//     -start by setting the whole line to grey
			if (beginIndex > -1 && endIndex <= $.codeTxt.length) $.codeTxt.setTextFormat(grey, beginIndex, endIndex);
			
			//    -evaluate comments
			index = lineTxt.indexOf("*");
			if (index >= 0) {
				lineTxt = lineTxt.substring(0, index); //remove comments from what you're evaluating
			}
			
			indents = 0;
			if (trim(lineTxt) != "") {			
				//    -evaluate indents
				
				for (var d:int = 1; d < lineTxt.length; d++) {
					if (lineTxt.charAt(d) != "." && lineTxt.charAt(d) != " ") break;
				}
				
				indents = lineTxt.substring(0, d).split(".").length;
				$.codeTxt.setTextFormat(black, beginIndex + 0, beginIndex + d);
				
				
				//    -evaluate whether operator line or method control line
				index = findIndentEnd(lineTxt);
				endIndex = findItemEnd(index, lineTxt);
				if (endIndex != 0) {
						operator = lineTxt.substring(index, endIndex).toLowerCase();
						operator = trim(operator);
						goalLine = false;
						branchLine = false;
					for each (var method in methods) {
						if ( operator == method  ) {
							goalLine = true;
							break;
						} else if (operator.substring(0,operator.length - 1) == method) { 
							operator = operator.substring(0,operator.length - 1); // get rid of colon
							goalLine = true;
							break;
						}
					}
					// check if it's a branch for Cog+
					for each (var branch in branches) {
						if ( operator == branch  ) {
							branchLine = true;
							break;
						} else if (operator.substring(0,operator.length - 1) == branch) { 
							operator = operator.substring(0, operator.length - 1); // get rid of colon
							branchLine = true;
							break;
						}
					}
					// index is the operator, endIndex the item after operator
					if (branchLine) {
						solarizeBranchLine(lineTxt, index, lineNum, beginIndex, endIndex, lineStartIndex);
					} else if (goalLine) {
						solarizeGoalLine(lineTxt, index, lineNum, beginIndex, endIndex, lineStartIndex);
					} else {
						solarizeOperatorLine(lineTxt, index, lineNum, beginIndex, endIndex, lineStartIndex, chunkNamedInError);
					}
				}
			} else return new Array(0, "goal", "", "", "", false, false, []); //returning true here means it won't be included in the interleaving process if it's a comment
					
			if (errorInLine == false && lineIsInErrors == true) errorFixed = true; //true means an error was fixed
			else errorFixed = false;
						
			return new Array(indents, operator, lineLabel, time, threadLabel, errorInLine, errorFixed, chunkNames);
		}
		
		//If WM detects an error in chunk usage, this line is called to highlight the offending chunk(s)
		public static function solarizeChunkOnLineNum(lineNum:int, chunkName:String):void {
			var beginIndex = WrappedLineUtils.getLineIndex($.codeTxt, lineNum);
			var endIndex = WrappedLineUtils.getLineEndIndex($.codeTxt, lineNum);
			var lineTxt:String = $.codeTxt.text.substring(beginIndex, endIndex);
			
			chunkName = "<" + chunkName + ">";
			var chunkStartIndex = lineTxt.indexOf(chunkName);
			var chunkEndIndex = chunkStartIndex + chunkName.length;
			
			$.codeTxt.setTextFormat(errorred, beginIndex + chunkStartIndex + 1, beginIndex + chunkEndIndex - 1);
		}

		//Purpose: removes a possible colon off the end of the operator
		//to make it be optional for parsing
		//Input: String: operator string
		//	Example: "CreateState: goal_name value"
		//Output: String: trimmed operator 
		//	Example: "CreateState goal_name value"
		private static function trimColon(operator: String): String {
			var colon:int = operator.indexOf(':');
			if (colon != -1) return (operator.substring(0, colon) + operator.substring(colon + 1, operator.length));
			return operator;
		}

		private static function solarizeBranchLine(lineTxt:String, index:int, lineNum:int, beginIndex:int, endIndex:int, lineStartIndex:int):void {
			//trace("index "+index+", beginIndex "+beginIndex+", endIndex "+endIndex+", lineStartIndex "+lineStartIndex);
			//for (var key: Object in $.stateTable) delete $.stateTable[key]; // clear out all $.stateTable
			lineLabel = "";
			time = "";
			threadLabel = "";

			// first color it magenta just like the methods
			$.codeTxt.setTextFormat(magenta, beginIndex + index, beginIndex + endIndex);
			// then evaluate what the operator is error handle based on the type of operator
			index = findNextItem(endIndex, lineTxt); 
			//trace("tirmmed "+trimmedLineTxt);
			endIndex = (lineStartIndex + lineTxt.length);

			//trace("begindex "+index);
			//trace("endIndex "+endIndex);
			//trace("line end index: "+(lineStartIndex + lineTxt.length));

			var tokens: Array = lineTxt.split(' ');
			switch (operator) {
				case "createstate":
					if (hasError(tokens, lineNum)) {
						ErrorColorLine(lineNum);
					} else if (index < endIndex) {
						createState(tokens[1], tokens[2]);
						$.codeTxt.setTextFormat(black, beginIndex + index, endIndex);
					}
					break;
				case "setstate":
					trace("case: "+operator);
					if (hasError(tokens, lineNum)) {
						SyntaxColor.ErrorColorLine(lineNum);
					} else {
						setState(tokens);
						$.codeTxt.setTextFormat(black, beginIndex + index, endIndex);
					}
					break;
				case "if":
					trace("case: "+operator);
				/*
					if (hasError(tokens, codeLines)) {
						SyntaxColor.ErrorColorLine(lineIndex);
					} else {
						//should return int of next line to be processed based on the resolution
						//of the if statement.
						lineIndex = nextIfLine(codeLines, lineIndex);
					}*/
					break;
				case "endif":
					trace("case: "+operator);
				/*
					if (hasError(tokens, codeLines)) {
						SyntaxColor.ErrorColorLine(lineIndex);
					}*/
					//ignore EndIfs, but are useful in processing original statement.
					break;
				case "goto":
					trace("case: "+operator);
				/*
					//Checks for infinite loops and syntax errors
					//Jumps are limited to 25, after which all jumps will be considered errors and not processed.
					if (jumps > 1 || hasError(tokens, codeLines)) {
						SyntaxColor.ErrorColorLine(lineIndex);
					} else {
						//line should be in the form "GoTo Goal: goal_name" (name can contain spaces)
						var goalTokens = frontTrimmedLine.split("Goal: ");
						var goalName = goalTokens[1];
						goalIndex = indexGoalLines(codeLines);
						if(goalIndex[goalName] !== undefined){
							lineIndex = goalIndex[goalName] - 1;
							jumps++;
						} else {
							SyntaxColor.ErrorColorLine(lineIndex);
						}
					}*/
					break;
			}

		}

		//Filter Method to get rid of empty strings in token array.  Taken from example
		//http://board.flashkit.com/board/showthread.php?805338-Remove-empty-elements-in-an-arry
		private static function noEmpty(item: * , index: int, array: Array): Boolean {
			return item != "";
		}

		//Purpose:  To determine if there is a syntax error in added operators
		//Input: front trimmed line tokenized using space as dilimiter. 
		//		 Operator should always be first token
		//       Example:  CreateState,target1,isFriendly,,,  <-whitespace at end of line
		//		 Example:  GoTo,Goal:,hands,and,feet
		//Output: Boolean 
		//		  True if hasError.
		//		  False if syntax is correct
		//
		//Notes: This function also checks for context errors such as states being defined twice
		//		 or trying access a state that doesn't exist.  Because of this, errors must be 
		//		 checked during processing instead of in ColorSyntax.
		//	
		//		 Does not handle infinite loops or invalid GoTo jumps.  Those are handled in
		//		 GenerateStepsArray when GoTo is processed.
		
		private static function hasError(tokens: Array, lineNum:int): Boolean {
			//Gets rid of empty tokens caused by whitespace
			tokens = tokens.filter(noEmpty);

			if (operator == "createstate") {
				//CreateState name value extraStuff
				//CreateState name
				//Name already exists
				if (tokens.length != 3) {
					errorInLine = true;
					$.errors[lineNum] = "I was expecting 2 arguments."
					return true;
				} else if ($.stateTable[tokens[1]] !== undefined && !typing) {
					errorInLine = true;
					$.errors[lineNum] = "'"+tokens[1]+"' already exists."
					return true;
				}
			} else if (operator == "setstate") {
				if(!(tokens.length == 3 || tokens.length == 4)){
					errorInLine = true;
					$.errors[lineNum] = "I was expecting 2 or 3 arguments."
					return true;
				} else if($.stateTable[tokens[1]] == undefined){
					errorInLine = true;
					$.errors[lineNum] = "'"+tokens[1]+"' does not exist."
					return true;
				} else if(tokens.length == 4){
					//Make sure the last field is a number between 0 and 1 inclusive on both sides.
					if(isNaN(tokens[3])){
						//trace("NaN: " + tokens[3] + " " + isNaN(tokens[4]));
						errorInLine = true;
						$.errors[lineNum] = "3rd argument should be a number between 0 and 1, but I got '"+tokens[3]+"'"
						return true;
					} else {
						var prob = Number(tokens[3]);
						if(!(0<= prob && prob <= 1)){
							errorInLine = true;
							$.errors[lineNum] = "Probability number should be between 0 and 1"
							return true;
						}
					}
				}
			} else if (operator == "if") {
				if (tokens.length != 3) {
					errorInLine = true;
					$.errors[lineNum] = "I was expecting 3 arguments."
				} else if ($.stateTable[tokens[1]] == undefined){
					errorInLine = true;
					$.errors[lineNum] = "'"+tokens[1]+"' does not exist."
					return true;
				}
			} else if (operator == "endif") {
				if (tokens.length != 1) {
					errorInLine = true;
					$.errors[lineNum] = "I was expecting 1 argument."
					return true;
				}
			} else if (operator == "goto") {
				if (tokens.length <= 2) {
					errorInLine = true;
					$.errors[lineNum] = "I was expecting 2 arguments."
					return true;
				}
				if (tokens.slice(0, 2).join(" ").toLowerCase() != "goto goal:")
					return true;
				/*var goalLabel = tokens.slice(2, tokens.length).join(" ");
				if(goalIndex[goalLabel] == undefined){
					return true;
				}*/
			}
			trace("no erors");
			if ($.errors[lineNum] !== undefined) delete $.errors[lineNum];
			errorInLine = false;
			return false;
		}
		
		//Purpose: Creates new state in the stateTable, all values are represented as strings.
		//Input: String key, String value (target1, visited)
		//Output: none
		//	SideEffect:  An new entry in global stateTable is added
		private static function createState(key: String, value: String) {
			$.stateTable[key] = value;
		}


		//Purpose: Changes an existing state in the stateTable, all values are represented as strings.
		//Input: Array:String line		
		//(Form) String key, String value (target1, visited)  OR
		//		 String key, String value (target1, visited), String probability (between 0 and 1) 

		//Output: none
		//	SideEffect:  An existing entry in global stateTable is changed
		private static function setState(line: Array) {
			if(line.length == 3){
				//trace("Found straight case.\n")
				$.stateTable[line[1]] = line[2];
			} else { //should have 4 tokens, SetState state_name value probability (number between 0-1) 
				var randomNumber:Number = Math.random();
				var givenProbability:Number = Number(line[3]);
				
				if(randomNumber < givenProbability){
					$.stateTable[line[1]] = line[2];
					//trace("Successfully set: " + line[0] + " " + line[1] + " " + line[2] + " " + line[3]);
				} else {
					//trace("RandomNumber did not exceed threshold: " + line[0] + " " + line[1] + " " + line[2] + " " + line[3]);
				}
			}
		}

		/*
		//Purpose: Finds next value of lineCounter. 
		//Input: Int lineCounter: lineNumber of Current If-statement
		//Output: int: the lineNumber of the next statement to be processed
		//	ifTrue: lineCounter - continue processing where you are.
		//	ifFalse: the line of the matching EndIf;
		private static function nextIfLine(lines: Array, lineCounter: int): int {
			var ifIsTrue: Boolean = evaluateIfStatement(trimIndents(lines[lineCounter]));
			if (ifIsTrue) {
				//do not jump any lines, lineCounter in parseloop will iterate to next line
				return lineCounter;
			} else {
				//Jump to the end of the ifStatement
				return findMatchingEndIf(lines, lineCounter);
			}
		}


		//Purpose: Returns the lineNumber of the matching EndIf
		//Input: Int lineCounter, the lineNumber of the current if statement
		//Output: int of the matching EndIf
		//		  if no ENDIF is found, returns end of program
		//Notes: Should handle nested ifs (fingers crossed)  
		//		 This method only runs when lines are to be skipped.
		//		 However, lines should still be colorized, so solarizeLine is called regardless

		private static function findMatchingEndIf(lines: Array, lineCounter: int): int {
			var numIfs: int = 1;
			var numEndIfs: int = 0;
			for (var i = lineCounter + 1; i < lines.length; i++) {
				SyntaxColor.solarizeLine(i);
				var frontTrimmedLine: String = trimIndents(lines[i]);
				var tokens: Array = frontTrimmedLine.split(' ');
				if (tokens[0] == "If") { //Handles nested ifs
					numIfs++; //for each if found, it must find an additional endif
				} else if (tokens[0] == "EndIf") {
					numEndIfs++;
					if (numEndIfs == numIfs) {
						return i;
					}
				}
			}
			return lines.length;
		}

		//Purpose: Checks the truth value of the input against the statetable
		//Input: String ifLine: already frontTrimmed line (If this_state isTrue)
		//Output: Boolean: if an entry in StateTable matches exactly the key and value
		//
		//Hint: if debugging, check that whitespace characters have been trimmed
		//in both the table and the input
		private static function evaluateIfStatement(ifLine: String): Boolean {
			//input must be in the form "If key value"
			var key: String = ifLine.split(' ')[1];
			var ifValue: String = ifLine.split(' ')[2];
			var tableValueString = $.stateTable[key];

			return (tableValueString == ifValue);
		}*/

		private static function solarizeGoalLine(lineTxt:String, index:int, lineNum:int, beginIndex:int, endIndex:int, lineStartIndex:int):void {
			$.codeTxt.setTextFormat(magenta, beginIndex + index, beginIndex + endIndex);
			
			//    -evaluate method name
			index = findNextItem(endIndex, lineTxt);
			endIndex = findLabelEnd(lineTxt, "as ");
			
			lineLabel = lineTxt.substring(index, endIndex);
			threadLabel = "base"; //set here, may be modified by also method below;
			if (lineLabel.length > 0) $.codeTxt.setTextFormat(black, beginIndex + index, beginIndex + endIndex);
			
			index = lineTxt.toLowerCase().indexOf("as ");
			endIndex = index + 3;
			if (operator == "also"){
				threadLabel = "!X!X!"; 
				if (index > -1) {// if "as" is used
					//set "as" magenta
					$.codeTxt.setTextFormat(magenta, beginIndex + index, beginIndex + endIndex);
					//determine thread name & color code
					index = findNextItem(endIndex, lineTxt);
					endIndex = index + lineTxt.length;
					threadLabel = lineTxt.substring(index, endIndex);
					if (threadLabel.length > 0) $.codeTxt.setTextFormat(black, beginIndex + index, beginIndex + index + threadLabel.length);
				}
			}
		}
		
		// 5 different errors can be detected with an operator:
		// "Couldn't find an operator."
		// "I was expecting a number after the left parenthesis."
		// "The modifier can be 'seconds', 'milliseconds', or 'ms'"
		// "I found a right paren before the left paren"
		// "I was expecting a right parenthesis."
		private static function solarizeOperatorLine(lineTxt:String, index:int, lineNum:int, beginIndex:int, endIndex:int, lineStartIndex:int, chunkNamedInError:String):void {
			threadLabel = ""; //setting for the return array			
			
			//    -evaluate operator
			var match:Boolean = false;
			for each (var op in $.operatorArray) {
				if (operator == op.appelation.toLowerCase()) {
					match = true;
					break;
				}
			}
			if (operator.length > 0) {
				if (!match) {
					$.errors[lineNum] = "Couldn't find an operator.";
					$.codeTxt.setTextFormat(errorred, beginIndex + index, beginIndex + endIndex);
					errorInLine = true;
				} else $.codeTxt.setTextFormat(blue, beginIndex + index, beginIndex + endIndex);
			}
				
				
			//    -evaluate label
			index = findNextItem(endIndex, lineTxt);
			endIndex = findLabelEnd(lineTxt, "(");
			lineLabel = lineTxt.substring(index, endIndex);
			if (lineLabel.length > 0) $.codeTxt.setTextFormat(black, beginIndex + index, beginIndex + endIndex);
				
			
			//    -evaluate WM chunks
			var leftAngleBracketIndex:int = 0;
			var rightAngleBracketIndex:int = 0;
			var leftAngleBracketIndices:Array = lineTxt.match(/</g);
			var rightAngleBracketIndices:Array = lineTxt.match(/>/g);
			if (leftAngleBracketIndices != null && rightAngleBracketIndices != null) {
				for (var i:int = 0; i < leftAngleBracketIndices.length; i++) {					
					leftAngleBracketIndex = lineTxt.indexOf(leftAngleBracketIndices[i], leftAngleBracketIndex);
					rightAngleBracketIndex = leftAngleBracketIndex + 1;
					rightAngleBracketIndex = lineTxt.indexOf(rightAngleBracketIndices[i], rightAngleBracketIndex);
					var chunkName = lineTxt.substring(leftAngleBracketIndex, rightAngleBracketIndex);	
										
					if (rightAngleBracketIndex > leftAngleBracketIndex + 1) {
						if (chunkNamedInError != chunkName) $.codeTxt.setTextFormat(cyan, beginIndex + leftAngleBracketIndex + 1, beginIndex + rightAngleBracketIndex);
						else $.codeTxt.setTextFormat(errorred, beginIndex + leftAngleBracketIndex + 1, beginIndex + rightAngleBracketIndex);
						chunkNames.push(lineTxt.substring(leftAngleBracketIndex + 1, rightAngleBracketIndex));
					}
					
					leftAngleBracketIndex = rightAngleBracketIndex + 1;
					rightAngleBracketIndex = leftAngleBracketIndex + 1;
				}
			}
			
			
			//    -evaluate time
			time = "";
			var leftParenIndex:int = lineTxt.indexOf("(");
			var rightParenIndex:int = lineTxt.indexOf(")");
			if (leftParenIndex > -1) {
				$.codeTxt.setTextFormat(black, beginIndex + leftParenIndex, beginIndex + leftParenIndex + 1); //set right paren to black
				
				//if the "(" marker exists
				if (rightParenIndex > -1 && rightParenIndex > leftParenIndex) {  //if the ")" marker exists and occurs after the left marker					
					$.codeTxt.setTextFormat(black, beginIndex + rightParenIndex, beginIndex + rightParenIndex + 1); //set right paren to black
					
					//find what's in the number position
					index = findNextItem(leftParenIndex + 1, lineTxt);
					endIndex = findItemEnd(index, lineTxt);
					var timeValue:String = lineTxt.substring(index, endIndex);
						timeValue = trim(timeValue);
					if ( isNaN(Number(timeValue) )  ) {
						$.errors[lineNum] = "I was expecting a number after the left parenthesis.";
						if (String(timeValue).length > 0) {
							$.codeTxt.setTextFormat(errorred, beginIndex + index, beginIndex + endIndex);
							time = ""; //if there is an error, blank out time so you don't try to evaluate it GomsProcessor
							errorInLine = true;
						} 
					} else {
						time = String(timeValue);
						$.codeTxt.setTextFormat(black, beginIndex + index, beginIndex + endIndex);
					}

					//find what's in the units position
					index = findNextItem(endIndex, lineTxt);
					endIndex = findLabelEnd(lineTxt,")") + 1;
					var timeUnits:String = (lineTxt.substring(index, endIndex)).toLowerCase();
						timeUnits = trim(timeUnits);
					if (String(timeValue).length > 0) { //only continue with the evaluation if you have a number in the first position
						if (timeUnits != "syllables" && timeUnits != "seconds" && timeUnits != "milliseconds" && timeUnits != "ms") {
							$.errors[lineNum] = "The modifier can be 'seconds', 'milliseconds', or 'ms'";
							if (timeUnits.length > 0) { 
								$.codeTxt.setTextFormat(errorred, beginIndex + index, beginIndex + endIndex);
								time = ""; //if there is an error, blank out time so you don't try to evaluate it GomsProcessor
								errorInLine = true;
							} 
						} else  {
							time = time + " " + timeUnits;
							$.codeTxt.setTextFormat(green, beginIndex + index, beginIndex + endIndex); //set units to green
						}
					}
					
				} else if (rightParenIndex < leftParenIndex && rightParenIndex > - 1) { //if there is a right paren before the left paren
						$.errors[lineNum] = "I found a right paren before the left paren";
						time = ""; //if there is an error, blank out time so you don't try to evaluate it GomsProcessor
						errorInLine = true;
						$.codeTxt.setTextFormat(errorred, beginIndex + rightParenIndex, beginIndex + rightParenIndex + 1);
				} else { // if there is a left paren with no right paren...
					$.errors[lineNum] = "I was expecting a right parenthesis.";
					time = ""; //if there is an error, blank out time so you don't try to evaluate it GomsProcessor
					errorInLine = true;
					$.codeTxt.setTextFormat(errorred, beginIndex + leftParenIndex, beginIndex + lineTxt.length);
				}

			}
		
		}
			
			
		private static function trim(s:String):String {
			return s.replace(/^[\s|\t|\n]+|[\s|\t|\n]+$/gs, '');
		}
		
		private static function countIdents(lineTxt:String):int {
			var indx:int = 0;
			indents = 0;
			while (lineTxt.charAt(indx) == " " || lineTxt.charAt(indx) == ".") {
				if (lineTxt.charAt(indx) == ".") indents++;
				indx++;
			}
			return indx++;
		}
		
		
		private static function findBeginIndex():int {
			var startPara:int = $.codeTxt.getFirstCharInParagraph($.codeTxt.getFirstCharInParagraph($.codeTxt.caretIndex));
			return startPara;
		}
		
		private static function findEndIndex(beginIndex:int):int {
			return ( beginIndex + $.codeTxt.getParagraphLength(beginIndex) );
		}
		
		
		private static function findLabelEnd(lineTxt:String, brkString:String):int {
			var endIndex:int = lineTxt.indexOf(brkString);
			if (endIndex == -1) endIndex = lineTxt.length;
			else endIndex--;
			
			return endIndex;
		}
		
		private static function findIndentEnd(lineTxt:String):int{
			for (var i:int = 0; i < lineTxt.length; i++){
				if (lineTxt.charAt(i) != " " && lineTxt.charAt(i) != ".") return i;
			}
			return lineTxt.length;
		}
		
		private static function findItemEnd(startIndex:int, lineTxt:String):int {
			var rslt:int = lineTxt.indexOf(" ", startIndex);
			if (rslt < 0) return lineTxt.length;
			else return rslt;
		}
		
		private static function findNextItem(startIndex:int, lineTxt:String):int {
			for (var i:int = startIndex; i < lineTxt.length; i++){
				//the && deals with consecutive delims
				//if (lineTxt.charAt(i) != " " && lineTxt.charAt(i - 1) == " ") return i;
				if (lineTxt.charAt(i) != " ") return i;
			}
			return lineTxt.length;
		}
		
	}
}
