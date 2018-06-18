#### Opioid Use and Misuse in The American Elderly Population
###### codename: opod
  
  This is the repository for the source code of the project "Opioid Use and Misuse in the American Elderly Population", as well as the slides presented at the 2018 U.S. National Library of Medicine 2018 Informatics Training Conference (Vanderbilt University, Nashville/TN) and a few other places.  
  
  Please notice that this code uses the NDC-to-ATC map table produced in a separate project: http://github.com/fabkury/ndc_map.  
  
  The code execution loosely follows the number sequence of the file names. However, the processing pipeline is not entirelly streamlined, meaning that manual intervention is required between some scripts. For example:
  * Due to the greediness of the NDC-to-ATC mapping process, not all drugs identified were accepted for analysis (cough medicines with opioids were excluded). The list of the generic names (GNNs) was exported, manually reviewed, then re-imported in file _OPOD - GGSSI.csv_.  
  * Some tables were constructed by manually executing parts of the code, then renaming the resulting intermediate tables.  
  
  Therefore, the publication of this source code is primarily intended to allow clarification of any minute technicality in the analyses. Secondarily, some may find it didactic to glance at its overall approach on how to process Medicare claims files, as available in the VRDC (CMS Virtual Research Data Center), all the way until final results.  
  
**--Fabrício Kury, postdoc at the U.S. National Library of Medicine**  
  
Search tags: medicare part d opioids ssri opioid use disorder oud drugs medications
