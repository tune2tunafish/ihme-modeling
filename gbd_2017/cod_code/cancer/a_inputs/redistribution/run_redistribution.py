
'''
Description:
Input(s):
Output(s):
How To Use: Pass dataset_id and data_type_id to main()
'''


import sys
import time
import pandas as pd
import os
from utils import(
    cluster_tools as cluster_tools,
    common_utils as utils,
    data_format_tools as dft, 
    pandas_expansions as pe
)
from a_inputs.a_mortality_incidence import (
    mi_dataset as md,
    cluster_utils_prep as cup
)
from registry_pipeline import cause_mapping as cm



def needs_rdp(df, ds_instance):
    ''' Quick check to determine if RDP needs to be run for the dataset
    '''
    ok_acause = cm.load_rdp_cause_map(ds_instance.data_type_id)[
        'acause'].unique()
    rdp_needed = (~df['acause'].isin(ok_acause) &
                  (df[ds_instance.metric] > 0))
    return(df.loc[rdp_needed, :].any().any())


def prep_input(df, ds_instance):
    ''' Returns the dataframe with added locations, corrected mapping, and
        restrictions applied
    '''
    print("    preparing data for redistribution...")
    # Format data for redistribution
    data_type_id = ds_instance.data_type_id
    metric_name = ds_instance.metric
    uid_cols = md.get_uid_cols(6)
    df = cm.restrict_causes(df, cause_col='acause',
                            data_type_id=data_type_id)
    group_cols = [c for c in uid_cols if c not in ['age', 'acause']]
    uids_added = dft.make_group_id_col(df, group_cols, id_col='uid')
    output = md.add_location_ids(uids_added)
    return(output)


def get_rdp_file(ds_instance, which_file='key', splitNum=None):
    ''' Accepts an MI_Dataset class and returns the 
    '''
    dsid = ds_instance.dataset_id
    dtid = ds_instance.data_type_id
    temp_dir = ds_instance.temp_folder
    if which_file == "rdp_input":
        this_file = "{}/{}_{}.h5".format(temp_dir, dsid, dtid)
    elif which_file == "split_output":
        this_file = "{}/{}_{}_split{}.csv".format(
            temp_dir, dsid, dtid, splitNum)
    if this_file:
        utils.ensure_dir(this_file)
        return(this_file)


def submit_rdp(input_data, this_dataset, is_resubmission):
    ''' Returns full dataset after redistribution.
        Separates data by submission requirement before submitting rdp for only
        only those data that require it
    '''
    def submission_requirement(df, uid): return needs_rdp(
        df[df['uid'] == uid], this_dataset)

    def output_file_function(id): return get_rdp_file(
        this_dataset, which_file='split_output', splitNum=id[2])

     # create a list of the uids that require redistribution and set aside a
    #   dataframe of the uids that do not require redistribution
    rdp_code_location = utils.get_path("redistribution",
                                       base="code_repo",
                                       process="mi_dataset")
    worker_script = rdp_code_location + "/rdp_worker.py"
    output_uids = md.get_uid_cols(7)
    header = "cncRDP_{}_{}".format(this_dataset.dataset_id, 
                                    this_dataset.data_type_id)
    rdp_input_file = get_rdp_file(this_dataset, which_file='rdp_input')
    #
    prepped_df = prep_input(input_data, this_dataset)
    submitted_data, unsubmitted_data = cup.split_submission_data(
                                                        prepped_df, 
                                                        'uid', 
                                                        submission_requirement, 
                                                        rdp_input_file)
    uid_list = submitted_data['uid'].unique().tolist()
    rdp_job_dict = cup.generate_prep_workers(worker_script,
                                            list_of_uids=uid_list,
                                            ds_instance=this_dataset,
                                            job_header=header,
                                            is_resubmission=is_resubmission,
                                            pace_interval=0.05)
    output_files = cup.get_results(rdp_job_dict,
                                    output_file_function,
                                    parent_process_name="rdp",
                                    noisy_checker=is_resubmission,
                                    add_resubmission_argument=is_resubmission,
                                    wait_time=5)
    # Re-combine compiled results with the set-aside data, before collapsing
    #   and testing
    final_results = pe.append_files(output_files)
    final_results = final_results.append(unsubmitted_data)
    # Re-set all 'under 5' data, then collapse to combine it with any existing
    #       'under 5' data
    final_results.loc[final_results['age'].lt(7) |
                        (final_results['age'].gt(90) &
                        final_results['age'].lt(95)),
                        'age'] = 2
    final_results = dft.collapse(final_results, by_cols=output_uids,
                            combine_cols = this_dataset.metric)
    return(final_results)


def main(dataset_id, data_type_id, is_resubmission):
    ''' Manages the redistribution process and runs each subprocess in order
    '''
    # Load data
    print("Preparing inputs...")
    this_dataset = md.MI_Dataset(dataset_id, 6, data_type_id)
    input_data = this_dataset.load_input()
    output_uids = md.get_uid_cols(7)
    # Delete previous outputs
    if not is_resubmission:
        print("Cleaning workspace...")
        utils.clean_directory_tree(this_dataset.temp_folder)
    # Exit if RDP is not needed
    if not needs_rdp(input_data, this_dataset):
        ok_acause = cm.load_rdp_cause_map(data_type_id)['acause'].unique()
        output_data = input_data.loc[input_data['acause'].isin(ok_acause)]
        md.complete_prep_step(output_data, this_dataset)
    else:
        final_results = submit_rdp(input_data, this_dataset, is_resubmission)
        # remove any cancer causes that did not exist in the input data
        output_acause = [a for a in input_data['acause'].unique() if a != "_gc"]
        final_results = final_results[final_results['acause'].isin(output_acause)]
        # Save and exit
        md.complete_prep_step(final_results, this_dataset)
        print("rdp complete.")



if __name__ == "__main__":
    dsid = sys.argv[1]
    dtid = int(sys.argv[2])
    is_resubmission = bool(int(sys.argv[3])) if len(sys.argv) > 3 else False
    main(dataset_id=dsid, data_type_id=dtid, is_resubmission=is_resubmission)
